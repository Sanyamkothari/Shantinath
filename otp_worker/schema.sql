-- Verification sessions: binds a MessageCentral verificationId to the phone it
-- was issued for, so a code validated for one number can never mint a token for
-- another.
CREATE TABLE IF NOT EXISTS otp_sessions (
  id          TEXT PRIMARY KEY,
  phone       TEXT NOT NULL,
  ip_hash     TEXT NOT NULL,
  consumed    INTEGER NOT NULL DEFAULT 0,
  attempts    INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);

-- Fixed-window send counters (ids are hashed; no raw phone/IP stored).
CREATE TABLE IF NOT EXISTS otp_rate_limits (
  id          TEXT PRIMARY KEY,
  count       INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_otp_sessions_expires ON otp_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_otp_rate_expires ON otp_rate_limits(expires_at);
