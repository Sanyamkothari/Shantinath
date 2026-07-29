const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const axios = require('axios');
const crypto = require('crypto');

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

// A verification session is only good for 10 minutes and 5 code attempts.
const OTP_SESSION_TTL_MS = 10 * 60 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;

// Server-only collections (no firestore.rules match => client access denied).
// Both carry `expiresAt`; add a Firestore TTL policy on that field for each so
// old rows are reaped automatically:
//   gcloud firestore fields ttls update expiresAt \
//     --collection-group=otp_sessions --enable-ttl
//   gcloud firestore fields ttls update expiresAt \
//     --collection-group=otp_rate_limits --enable-ttl
const OTP_SESSIONS = 'otp_sessions';
const OTP_RATE_LIMITS = 'otp_rate_limits';

// Send quotas. Each OTP send costs real money and rings a real phone, so the
// endpoint is metered per number and per caller IP before MessageCentral is
// ever contacted.
const SEND_LIMITS = [
  { scope: 'phone', windowMs: 15 * 60 * 1000, max: 10 },
  { scope: 'phone', windowMs: 24 * 60 * 60 * 1000, max: 50 },
  { scope: 'ip', windowMs: 60 * 60 * 1000, max: 100 },
];

/** Returns the configured MessageCentral auth token. */
function getMcToken() {
  let token = process.env.MC_AUTH_TOKEN;
  if (!token && typeof MC_AUTH_TOKEN !== 'undefined') {
    try {
      token = MC_AUTH_TOKEN.value();
    } catch (_) {}
  }
  if (!token) {
    logger.error('MC_AUTH_TOKEN secret is not configured.');
    throw new Error('MC_AUTH_TOKEN secret is not configured.');
  }
  return token;
}

/** Best-effort caller IP. Cloud Run sits behind a proxy, so prefer the
 *  left-most X-Forwarded-For entry and fall back to the socket address. */
function clientIp(req) {
  const fwd = req.headers['x-forwarded-for'];
  const first = typeof fwd === 'string' ? fwd.split(',')[0].trim() : '';
  return first || req.ip || 'unknown';
}

function sha256(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

/** Fixed-window counter doc id. IPs and phone numbers are hashed so the
 *  rate-limit collection never stores raw identifiers. */
function rateDocId(scope, value, windowMs, now) {
  return `${scope}_${sha256(`${scope}:${value}`).slice(0, 32)}_${windowMs}_${Math.floor(now / windowMs)}`;
}

/**
 * Atomically checks every quota and increments them all only if every one has
 * headroom. Consumed BEFORE the SMS is sent, so a MessageCentral failure still
 * costs quota — failing closed is the right direction for a paid side effect.
 * Returns { allowed: boolean, scope?: string }.
 */
async function consumeSendQuota(entries, now) {
  const refs = entries.map((e) =>
    db.collection(OTP_RATE_LIMITS).doc(rateDocId(e.scope, e.value, e.windowMs, now)));

  return db.runTransaction(async (tx) => {
    const snaps = await tx.getAll(...refs);
    const counts = snaps.map((s) => (s.exists && s.data().count) || 0);

    for (let i = 0; i < entries.length; i++) {
      if (counts[i] >= entries[i].max) {
        return { allowed: false, scope: entries[i].scope };
      }
    }
    for (let i = 0; i < entries.length; i++) {
      tx.set(refs[i], {
        count: counts[i] + 1,
        // Keep the row a full extra window so a late read never resurrects a
        // bucket that TTL already reaped mid-window.
        expiresAt: new Date(now + entries[i].windowMs * 2),
      }, { merge: true });
    }
    return { allowed: true };
  });
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

    let body = req.body || {};
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch (_) {}
    }
    const { phone } = body || {};
    if (typeof phone !== 'string' || phone.length !== 10 || !/^\d{10}$/.test(phone)) {
      return res.status(400).json({ error: 'Valid 10-digit phone number is required' });
    }

    // Meter before spending money / ringing a phone. This endpoint is public,
    // so without it anyone can drain the MessageCentral balance or SMS-bomb a
    // victim by replaying this call.
    const now = Date.now();
    const ip = clientIp(req);
    let quota;
    try {
      quota = await consumeSendQuota(
        SEND_LIMITS.map((l) => ({ ...l, value: l.scope === 'phone' ? phone : ip })),
        now,
      );
    } catch (err) {
      logger.error('OTP send quota check failed:', err);
      return res.status(503).json({ error: 'Service busy. Please try again shortly.' });
    }
    if (!quota.allowed) {
      logger.warn(`OTP send throttled (${quota.scope}) for ******${phone.slice(-4)}`);
      return res.status(429).json({
        error: 'Too many OTP requests. Please wait a few minutes and try again.',
      });
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
        // Bind this verificationId to THIS phone number. verifyOtp mints the
        // Firebase token for the phone recorded here, never for whatever the
        // client claims — otherwise anyone could validate an OTP issued to
        // their own number and be handed a token for someone else's.
        await db.collection(OTP_SESSIONS).doc(String(verificationId)).set({
          phone,
          ipHash: sha256(ip),
          consumed: false,
          attempts: 0,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: new Date(now + OTP_SESSION_TTL_MS),
        });

        // Log only the last 4 digits — Cloud Logging is retained and broadly
        // readable, so full subscriber numbers should not land in it.
        logger.info(`OTP sent to ******${phone.slice(-4)} (verificationId ${verificationId})`);
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

    let body = req.body || {};
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch (_) {}
    }
    const { phone, verificationId, otp } = body || {};
    if (typeof phone !== 'string' || !/^\d{10}$/.test(phone)) {
      return res.status(400).json({ error: 'Valid 10-digit phone number is required' });
    }
    const expiredMsg = 'Verification session expired. Please request a new OTP.';
    // The id becomes a Firestore document path, so reject anything that isn't
    // the plain token MessageCentral issues — a value containing '/' would make
    // .doc() throw outside any handler.
    if (typeof verificationId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(verificationId)) {
      return res.status(400).json({ error: expiredMsg });
    }
    if (!otp || otp.length !== OTP_LENGTH) {
      return res.status(400).json({ error: `Valid ${OTP_LENGTH}-digit OTP code is required` });
    }

    const sessionRef = db.collection(OTP_SESSIONS).doc(verificationId);

    // Claim one attempt against the session BEFORE talking to MessageCentral.
    // Doing it in a transaction is what makes the 5-attempt cap hold against
    // concurrent guesses; checking then writing would let a burst slip past.
    // `sessionError` is tagged so a genuine Firestore failure (which also
    // carries a `.code`) is not mistaken for one of these rejections.
    const sessionError = (reason, httpStatus, msg) =>
      Object.assign(new Error(reason), { __otpReject: true, httpStatus, msg });

    let boundPhone;
    try {
      boundPhone = await db.runTransaction(async (tx) => {
        const snap = await tx.get(sessionRef);
        if (!snap.exists) throw sessionError('no_session', 400, expiredMsg);

        const s = snap.data();
        const expiresAt = s.expiresAt && s.expiresAt.toDate ? s.expiresAt.toDate() : s.expiresAt;
        if (s.consumed) {
          throw sessionError('consumed', 400, 'This code was already used. Please request a new one.');
        }
        if (!expiresAt || expiresAt.getTime() < Date.now()) {
          throw sessionError('expired', 400, expiredMsg);
        }
        if ((s.attempts || 0) >= MAX_VERIFY_ATTEMPTS) {
          throw sessionError('too_many', 429, 'Too many attempts. Please request a new OTP.');
        }

        tx.update(sessionRef, { attempts: (s.attempts || 0) + 1 });
        return s.phone;
      });
    } catch (err) {
      if (err && err.__otpReject) {
        if (err.message === 'too_many' || err.message === 'consumed') {
          logger.warn(`verifyOtp rejected (${err.message}) for verificationId ${verificationId}`);
        }
        return res.status(err.httpStatus).json({ error: err.msg });
      }
      logger.error('Error loading OTP session:', err);
      return res.status(500).json({ error: 'Could not verify OTP. Please try again.' });
    }

    // The session decides whose token this is. A mismatch means the client sent
    // a phone it was not issued this verificationId for — the account-takeover
    // shape — so refuse rather than silently minting for boundPhone.
    if (boundPhone !== phone) {
      logger.error(
        `verifyOtp phone/session mismatch: session ${verificationId} was issued for ` +
        `******${String(boundPhone || '').slice(-4)}, request claimed ******${phone.slice(-4)}`,
      );
      return res.status(400).json({ error: expiredMsg });
    }

    try {
      const token = getMcToken();
      let mc;
      try {
        // MessageCentral's validateOtp is a GET (send is POST). Calling it with
        // POST returns 401 (empty body) — confirmed by MC support, ticket #20285.
        const response = await axios.get(
          `${MC_BASE_URL}/verification/v3/validateOtp`,
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
        // Burn the session first so a replay of the same (verificationId, otp)
        // cannot mint a second token.
        await sessionRef.update({
          consumed: true,
          consumedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Mint a Firebase custom token for the phone the session was issued to.
        // UID = phone; the phone_number claim populates
        // request.auth.token.phone_number for the Firestore security rules.
        const customToken = await admin.auth().createCustomToken(boundPhone, {
          phone_number: `+91${boundPhone}`,
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
  // customerId can be absent on malformed docs; a TypeError here would fail the
  // trigger and get it retried forever.
  const actorId = data.placedById || (data.customerId || '').replace('+91', '');
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
