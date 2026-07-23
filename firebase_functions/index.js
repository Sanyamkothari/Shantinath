const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();
const db = admin.firestore();

// MessageCentral VerifyNow auth token (a long-lived JWT from the dashboard),
// stored as a Secret Manager secret. Set once with:
//   firebase functions:secrets:set MC_AUTH_TOKEN
// MessageCentral passes this token directly in the `authToken` header of the
// send/validate calls (see their API docs), so no per-request token generation
// is needed. Rotate it from the dashboard before it expires (~5 years).
const MC_AUTH_TOKEN = defineSecret('MC_AUTH_TOKEN');

// Must match AppConstants.cloudFunctionsRegion in the Flutter app.
const REGION = 'us-central1';

const MC_BASE_URL = 'https://cpaas.messagecentral.com';
const OTP_LENGTH = 6;

/** Returns the configured MessageCentral auth token. */
function getMcToken() {
  const token = MC_AUTH_TOKEN.value();
  if (!token) {
    throw new Error('MC_AUTH_TOKEN secret is not configured.');
  }
  return token;
}

/** Maps a MessageCentral verify responseCode to a user-facing message. */
function mcErrorMessage(code) {
  switch (String(code)) {
    case '702': return 'Invalid verification code. Please try again.';
    case '705': return 'This code has expired. Please request a new one.';
    case '703': return 'This code was already used. Please request a new one.';
    case '800': return 'Too many attempts. Please request a new OTP.';
    case '505': return 'Verification session expired. Please request a new OTP.';
    default: return 'Failed to verify OTP. Please try again.';
  }
}

/**
 * Sends an OTP via MessageCentral VerifyNow.
 * Expects JSON: { "phone": "10_digit_number" }
 * Returns: { success: true, verificationId } — verificationId is needed to validate.
 */
exports.sendOtp = onRequest(
  { region: REGION, cors: true, secrets: [MC_AUTH_TOKEN], invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Method not allowed' });
    }

    const { phone } = req.body || {};
    if (!phone || phone.length !== 10 || !/^\d+$/.test(phone)) {
      return res.status(400).json({ error: 'Valid 10-digit phone number is required' });
    }

    try {
      const token = getMcToken();
      const response = await axios.post(
        `${MC_BASE_URL}/verification/v3/send`,
        null,
        {
          params: {
            countryCode: '91',
            flowType: 'SMS',
            mobileNumber: phone,
            otpLength: OTP_LENGTH,
          },
          headers: { authToken: token },
        }
      );

      const data = response.data && response.data.data;
      const verificationId = data && data.verificationId;
      if (response.data && String(response.data.responseCode) === '200' && verificationId) {
        logger.info(`OTP sent to ${phone} (verificationId ${verificationId})`);
        return res.status(200).json({ success: true, verificationId: String(verificationId) });
      }

      logger.error('MessageCentral send error:', response.data);
      return res.status(502).json({
        error: (data && data.errorMessage) || 'Failed to send OTP. Please try again.',
      });
    } catch (error) {
      logger.error('Error sending OTP:', error.response ? error.response.data : error.message);
      return res.status(500).json({ error: 'Could not send OTP. Please try again.' });
    }
  }
);

/**
 * Validates an OTP via MessageCentral and mints a Firebase custom token on success.
 * Expects JSON: { "phone": "...", "verificationId": "...", "otp": "6_digit_code" }
 * Returns: { success: true, customToken }
 */
exports.verifyOtp = onRequest(
  { region: REGION, cors: true, secrets: [MC_AUTH_TOKEN], invoker: 'public' },
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Method not allowed' });
    }

    const { phone, verificationId, otp } = req.body || {};
    if (!phone || phone.length !== 10) {
      return res.status(400).json({ error: 'Valid 10-digit phone number is required' });
    }
    if (!verificationId) {
      return res.status(400).json({ error: 'Verification session expired. Please request a new OTP.' });
    }
    if (!otp || otp.length !== OTP_LENGTH) {
      return res.status(400).json({ error: `Valid ${OTP_LENGTH}-digit OTP code is required` });
    }

    try {
      const token = getMcToken();
      let mc;
      try {
        const response = await axios.post(
          `${MC_BASE_URL}/verification/v3/validateOtp`,
          null,
          {
            params: { verificationId, code: otp.trim() },
            headers: { authToken: token },
          }
        );
        mc = response.data;
      } catch (err) {
        // MessageCentral returns non-2xx (e.g. wrong/expired OTP) with a body.
        mc = err.response && err.response.data;
        if (!mc) throw err;
      }

      const inner = mc && mc.data;
      const status = inner && inner.verificationStatus;
      const code = (inner && inner.responseCode) || (mc && mc.responseCode);

      if (String(code) === '200' && status === 'VERIFICATION_COMPLETED') {
        // Mint a Firebase custom token. UID = phone; phone_number claim populates
        // request.auth.token.phone_number for the Firestore security rules.
        const customToken = await admin.auth().createCustomToken(phone, {
          phone_number: `+91${phone}`,
        });
        return res.status(200).json({ success: true, customToken });
      }

      logger.warn('OTP validation failed:', mc);
      return res.status(400).json({ error: mcErrorMessage(code) });
    } catch (error) {
      logger.error('Error verifying OTP:', {
        message: error.message,
        stack: error.stack,
        responseStatus: error.response ? error.response.status : undefined,
        responseData: error.response ? error.response.data : undefined,
      });
      return res.status(500).json({ error: 'Could not verify OTP. Please try again.' });
    }
  }
);

/**
 * Firestore triggers to track order creation, modifications, and permissions changes in activity logs.
 */
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');

exports.onOrderCreated = onDocumentCreated({
  region: REGION,
  document: 'orders/{orderId}'
}, async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    logger.warn('No snapshot data in onOrderCreated');
    return;
  }
  const data = snapshot.data();
  const orderId = event.params.orderId;
  const actorId = data.placedById || data.customerId.replace('+91', '');
  const actorName = data.placedByName || data.customerName || 'Customer';
  const actorRole = data.placedById ? 'employee' : 'customer';

  let summary = `Order #${orderId.substring(0, 8)} of ₹${data.totalAmount} was placed by ${actorName}.`;
  if (data.placedByName) {
    summary = `Employee ${data.placedByName} placed order #${orderId.substring(0, 8)} (₹${data.totalAmount}) on behalf of customer ${data.customerName}.`;
  } else {
    summary = `Customer ${data.customerName} placed order #${orderId.substring(0, 8)} (₹${data.totalAmount}).`;
  }

  try {
    await db.collection('activity_logs').add({
      action: 'order_placed',
      actorId: actorId,
      actorName: actorName,
      actorRole: actorRole,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      summary: summary,
      targetId: orderId,
      targetType: 'order',
      metadata: {
        totalAmount: data.totalAmount,
        itemCount: (data.items || []).length,
      }
    });
  } catch (err) {
    logger.error('Error in onOrderCreated trigger:', err);
  }
});

exports.onOrderUpdated = onDocumentUpdated({
  region: REGION,
  document: 'orders/{orderId}'
}, async (event) => {
  const change = event.data;
  if (!change) return;
  const beforeData = change.before.data();
  const afterData = change.after.data();

  const statusChanged = beforeData.status !== afterData.status;
  const itemsChanged = JSON.stringify(beforeData.items || []) !== JSON.stringify(afterData.items || []);
  const amountChanged = beforeData.totalAmount !== afterData.totalAmount;

  if (statusChanged || itemsChanged || amountChanged) {
    const orderId = event.params.orderId;
    const actorId = afterData.lastModifiedById || 'system';
    const actorName = afterData.lastModifiedByName || 'System / Admin';
    const actorRole = afterData.lastModifiedById ? 'staff' : 'admin';

    let changeSummary = `Order #${orderId.substring(0, 8)} was modified by ${actorName}.`;
    if (statusChanged) {
      changeSummary = `Order #${orderId.substring(0, 8)} status changed from ${beforeData.status} to ${afterData.status} by ${actorName}.`;
    } else if (itemsChanged || amountChanged) {
      changeSummary = `Order #${orderId.substring(0, 8)} items/quantities updated by ${actorName}.`;
    }

    try {
      await db.collection('activity_logs').add({
        action: 'order_modified',
        actorId: actorId,
        actorName: actorName,
        actorRole: actorRole,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        summary: changeSummary,
        targetId: orderId,
        targetType: 'order',
        metadata: {
          oldStatus: beforeData.status,
          newStatus: afterData.status,
          oldAmount: beforeData.totalAmount,
          newAmount: afterData.totalAmount,
        }
      });
    } catch (err) {
      logger.error('Error in onOrderUpdated trigger:', err);
    }
  }
});

// Note: permission/role changes (permissions_changed, employee_added, employee_removed)
// are logged client-side with the real acting admin as the actor — see
// employee_permissions_screen.dart and manage_employees_screen.dart. A server-side
// onUserUpdated trigger was intentionally removed to avoid duplicate, 'system'-
// attributed audit rows. User-doc writes are restricted by firestore.rules.
