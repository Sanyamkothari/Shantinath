// OTP login backend for Shantinath Agro, running on Cloudflare Workers (free
// tier) so the Firebase project can stay on the Spark plan.
//
//   POST /sendOtp    { phone, requireRegistered? } -> { success, verificationId }
//   POST /verifyOtp  { phone, verificationId, otp } -> { success, customToken }
//
// Same request/response contract as the former Cloud Functions, so the Flutter
// login screens are unchanged. State (verification sessions, send quotas) lives
// in D1; Firestore is only touched over REST to check that users/{phone} exists.

const MC_BASE_URL = 'https://cpaas.messagecentral.com';
const OTP_LENGTH = 6;

const OTP_SESSION_TTL_MS = 10 * 60 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;

const SEND_LIMITS = [
  { scope: 'phone', windowMs: 15 * 60 * 1000, max: 10 },
  { scope: 'phone', windowMs: 24 * 60 * 60 * 1000, max: 50 },
  { scope: 'ip', windowMs: 60 * 60 * 1000, max: 100 },
];

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

async function sha256Hex(value) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(value)));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// ── Google service-account helpers (Firestore REST + Firebase custom tokens) ──

function b64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

let cachedKey = null; // { pem, key }
async function importPrivateKey(pem) {
  if (cachedKey && cachedKey.pem === pem) return cachedKey.key;
  const der = Uint8Array.from(
    atob(pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '')),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  cachedKey = { pem, key };
  return key;
}

async function signJwt(sa, payload) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${b64url(sig)}`;
}

function loadServiceAccount(env) {
  if (!env.FIREBASE_SA_KEY) throw new Error('FIREBASE_SA_KEY secret is not configured.');
  const sa = JSON.parse(env.FIREBASE_SA_KEY);
  if (!sa.private_key || !sa.client_email || !sa.project_id) {
    throw new Error('FIREBASE_SA_KEY is not a valid service-account JSON.');
  }
  return sa;
}

/** Firebase custom token (uid = phone, phone_number claim for the rules). */
async function mintCustomToken(sa, phone) {
  const now = Math.floor(Date.now() / 1000);
  return signJwt(sa, {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
    iat: now,
    exp: now + 3600,
    uid: phone,
    claims: { phone_number: `+91${phone}` },
  });
}

let cachedAccess = null; // { token, exp }
async function getAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccess && cachedAccess.exp - 60 > now) return cachedAccess.token;

  const assertion = await signJwt(sa, {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`Google token exchange failed (${res.status})`);
  const data = await res.json();
  cachedAccess = { token: data.access_token, exp: now + (data.expires_in || 3600) };
  return cachedAccess.token;
}

/** True when users/{phone} exists in Firestore (Admin-level read). */
async function userExists(sa, phone) {
  const token = await getAccessToken(sa);
  const url =
    `https://firestore.googleapis.com/v1/projects/${sa.project_id}` +
    `/databases/(default)/documents/users/${phone}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 200) return true;
  if (res.status === 404) return false;
  throw new Error(`Firestore lookup failed (${res.status})`);
}

// ── Rate limiting ──

/**
 * Consumes one unit from every quota bucket. Each bucket is a conditional
 * upsert, so the check-and-increment is atomic per bucket and a concurrent burst
 * cannot overshoot. Buckets already incremented before a later one denies stay
 * incremented, which only ever errs towards throttling more.
 */
async function consumeSendQuota(db, entries, now) {
  for (const e of entries) {
    const windowIndex = Math.floor(now / e.windowMs);
    const id = `${e.scope}_${(await sha256Hex(`${e.scope}:${e.value}`)).slice(0, 32)}_${e.windowMs}_${windowIndex}`;
    const res = await db
      .prepare(
        `INSERT INTO otp_rate_limits (id, count, expires_at) VALUES (?1, 1, ?2)
         ON CONFLICT(id) DO UPDATE SET count = count + 1 WHERE count < ?3`,
      )
      .bind(id, now + e.windowMs * 2, e.max)
      .run();
    if (!res.meta || res.meta.changes === 0) return { allowed: false, scope: e.scope };
  }
  return { allowed: true };
}

// ── MessageCentral ──

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

async function readJson(request) {
  try {
    const body = await request.json();
    return body && typeof body === 'object' ? body : {};
  } catch (_) {
    return {};
  }
}

function maskPhone(phone) {
  return `******${String(phone).slice(-4)}`;
}

// ── POST /sendOtp ──

async function sendOtp(request, env) {
  const body = await readJson(request);
  const { phone } = body;
  if (typeof phone !== 'string' || !/^\d{10}$/.test(phone)) {
    return json(400, { error: 'Valid 10-digit phone number is required' });
  }
  if (!env.MC_AUTH_TOKEN) {
    console.error('MC_AUTH_TOKEN secret is not configured.');
    return json(500, { error: 'Could not send OTP. Please try again.' });
  }

  const now = Date.now();
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';

  // Meter before spending money / ringing a phone: this endpoint is public.
  let quota;
  try {
    quota = await consumeSendQuota(
      env.DB,
      SEND_LIMITS.map((l) => ({ ...l, value: l.scope === 'phone' ? phone : ip })),
      now,
    );
  } catch (err) {
    console.error('OTP send quota check failed:', err);
    return json(503, { error: 'Service busy. Please try again shortly.' });
  }
  if (!quota.allowed) {
    console.warn(`OTP send throttled (${quota.scope}) for ${maskPhone(phone)}`);
    return json(429, { error: 'Too many OTP requests. Please wait a few minutes and try again.' });
  }

  // Login-only pre-check, after the quota so it cannot enumerate registered
  // numbers faster than OTPs could be requested anyway.
  if (body.requireRegistered === true) {
    let exists;
    try {
      exists = await userExists(loadServiceAccount(env), phone);
    } catch (err) {
      console.error('OTP registration pre-check failed:', err);
      return json(503, { error: 'Service busy. Please try again shortly.' });
    }
    if (!exists) {
      return json(404, {
        success: false,
        code: 'NOT_REGISTERED',
        error: 'This number is not registered. Please register first.',
      });
    }
  }

  try {
    const url = new URL(`${MC_BASE_URL}/verification/v3/send`);
    url.search = new URLSearchParams({
      countryCode: '91',
      flowType: 'SMS',
      mobileNumber: phone,
      otpLength: String(OTP_LENGTH),
    }).toString();
    const res = await fetch(url, { method: 'POST', headers: { authToken: env.MC_AUTH_TOKEN } });
    const payload = await res.json().catch(() => null);

    const data = payload && payload.data;
    const verificationId = data && data.verificationId;
    if (payload && String(payload.responseCode) === '200' && verificationId) {
      // Bind this verificationId to THIS phone; verifyOtp mints the token for
      // the phone recorded here, never for whatever the client claims.
      await env.DB
        .prepare(
          `INSERT INTO otp_sessions (id, phone, ip_hash, consumed, attempts, created_at, expires_at)
           VALUES (?1, ?2, ?3, 0, 0, ?4, ?5)`,
        )
        .bind(String(verificationId), phone, await sha256Hex(ip), now, now + OTP_SESSION_TTL_MS)
        .run();

      console.log(`OTP sent to ${maskPhone(phone)} (verificationId ${verificationId})`);
      return json(200, { success: true, verificationId: String(verificationId) });
    }

    console.error('MessageCentral send error:', JSON.stringify(payload));
    return json(502, {
      error: (data && data.errorMessage) || 'Failed to send OTP. Please try again.',
    });
  } catch (err) {
    console.error('Error sending OTP:', err && err.message);
    return json(500, { error: 'Could not send OTP. Please try again.' });
  }
}

// ── POST /verifyOtp ──

async function verifyOtp(request, env) {
  const body = await readJson(request);
  const { phone, verificationId, otp } = body;
  const expiredMsg = 'Verification session expired. Please request a new OTP.';

  if (typeof phone !== 'string' || !/^\d{10}$/.test(phone)) {
    return json(400, { error: 'Valid 10-digit phone number is required' });
  }
  if (typeof verificationId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(verificationId)) {
    return json(400, { error: expiredMsg });
  }
  if (typeof otp !== 'string' || otp.trim().length !== OTP_LENGTH) {
    return json(400, { error: `Valid ${OTP_LENGTH}-digit OTP code is required` });
  }
  if (!env.MC_AUTH_TOKEN) {
    console.error('MC_AUTH_TOKEN secret is not configured.');
    return json(500, { error: 'Could not verify OTP. Please try again.' });
  }

  const db = env.DB;
  const now = Date.now();

  // Claim one attempt BEFORE talking to MessageCentral. The conditional UPDATE
  // is atomic, which is what makes the attempt cap hold against concurrent
  // guesses.
  let session;
  try {
    const claim = await db
      .prepare(
        `UPDATE otp_sessions SET attempts = attempts + 1
         WHERE id = ?1 AND consumed = 0 AND expires_at > ?2 AND attempts < ?3`,
      )
      .bind(verificationId, now, MAX_VERIFY_ATTEMPTS)
      .run();

    session = await db
      .prepare('SELECT phone, consumed, attempts, expires_at FROM otp_sessions WHERE id = ?1')
      .bind(verificationId)
      .first();

    if (!claim.meta || claim.meta.changes === 0) {
      if (!session) return json(400, { error: expiredMsg });
      if (session.consumed) {
        console.warn(`verifyOtp rejected (consumed) for verificationId ${verificationId}`);
        return json(400, { error: 'This code was already used. Please request a new one.' });
      }
      if (session.expires_at <= now) return json(400, { error: expiredMsg });
      console.warn(`verifyOtp rejected (too_many) for verificationId ${verificationId}`);
      return json(429, { error: 'Too many attempts. Please request a new OTP.' });
    }
  } catch (err) {
    console.error('Error loading OTP session:', err);
    return json(500, { error: 'Could not verify OTP. Please try again.' });
  }

  // The session decides whose token this is; a mismatch is the account-takeover
  // shape, so refuse rather than silently minting for the session's phone.
  if (session.phone !== phone) {
    console.error(
      `verifyOtp phone/session mismatch: session ${verificationId} was issued for ` +
        `${maskPhone(session.phone)}, request claimed ${maskPhone(phone)}`,
    );
    return json(400, { error: expiredMsg });
  }

  try {
    const url = new URL(`${MC_BASE_URL}/verification/v3/validateOtp`);
    url.search = new URLSearchParams({ verificationId, code: otp.trim() }).toString();
    // validateOtp is a GET (send is POST) — confirmed by MessageCentral support.
    const res = await fetch(url, { method: 'GET', headers: { authToken: env.MC_AUTH_TOKEN } });
    const mc = await res.json().catch(() => null);

    const inner = mc && mc.data;
    const status = inner && inner.verificationStatus;
    const code = (inner && inner.responseCode) || (mc && mc.responseCode);

    if (String(code) === '200' && status === 'VERIFICATION_COMPLETED') {
      // Burn the session first; the conditional update means two concurrent
      // requests with the same (verificationId, otp) cannot both mint a token.
      const burn = await db
        .prepare('UPDATE otp_sessions SET consumed = 1 WHERE id = ?1 AND consumed = 0')
        .bind(verificationId)
        .run();
      if (!burn.meta || burn.meta.changes === 0) {
        return json(400, { error: 'This code was already used. Please request a new one.' });
      }

      const customToken = await mintCustomToken(loadServiceAccount(env), session.phone);
      return json(200, { success: true, customToken });
    }

    console.warn('OTP validation failed:', JSON.stringify(mc));
    return json(400, { error: mcErrorMessage(code) });
  } catch (err) {
    console.error('Error verifying OTP:', err && err.message);
    return json(500, { error: 'Could not verify OTP. Please try again.' });
  }
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    const { pathname } = new URL(request.url);
    const route = pathname.replace(/\/+$/, '');

    if (route !== '/sendOtp' && route !== '/verifyOtp') {
      return json(404, { error: 'Not found' });
    }
    if (request.method !== 'POST') {
      return json(405, { error: 'Method not allowed' });
    }
    return route === '/sendOtp' ? sendOtp(request, env) : verifyOtp(request, env);
  },

  // Daily cron: reap expired sessions and rate-limit buckets.
  async scheduled(_event, env) {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare('DELETE FROM otp_sessions WHERE expires_at < ?1').bind(now),
      env.DB.prepare('DELETE FROM otp_rate_limits WHERE expires_at < ?1').bind(now),
    ]);
  },
};
