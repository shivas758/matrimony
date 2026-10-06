// One-time codes for agent signup and customer login — SPEC §9.1.
//
// The code itself is never stored: otp_codes keeps sha256(secret|phone|purpose|code),
// an expiry, an attempt counter and consumed_at (a code is verified once).
// Per (phone, purpose): OTP_RESEND_SECONDS between sends, OTP_MAX_SENDS_PER_HOUR
// sends per hour, OTP_MAX_ATTEMPTS wrong guesses per code.
//
// Switching from mock to production (no code change — see .env.example):
//   OTP_PROVIDER=msg91
//   MSG91_AUTH_KEY=<your MSG91 auth key>
//   MSG91_TEMPLATE_ID=<the DLT-approved OTP template id>
//   MSG91_SENDER=<6-char sender id, optional>
//   OTP_MOCK_ECHO is ignored for a real provider (never echoed).
// then restart the API. In mock mode nothing is sent: generateCode() always
// returns OTP_MOCK_CODE (default 123456) and the send response echoes it as
// `mock_code` when OTP_MOCK_ECHO=true so the apps can show "Test mode".

import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { one, query } from './db.js';
import { ApiError } from './errors.js';

const MSG91_OTP_URL = 'https://control.msg91.com/api/v5/otp';

/** sha256 hex of secret|phone|purpose|code — what otp_codes.code_hash holds. */
export function hashOtp(phone, purpose, code) {
  return createHash('sha256')
    .update(`${config.jwtSecret}|${phone}|${purpose}|${code}`)
    .digest('hex');
}

/** A 6-digit code. Mock provider: always OTP_MOCK_CODE, so testers know it. */
export function generateCode() {
  if (config.otp.provider === 'mock') return config.otp.mockCode;
  return String(randomInt(0, 1_000_000)).padStart(6, '0');
}

/**
 * Delivers `code` to `phone`. mock → console only. msg91 → MSG91 OTP API with
 * our own code (the verify logic stays identical for both providers).
 * Any provider problem is a 503 otp_provider_error — nothing is stored then.
 */
export async function sendOtpSms(phone, code) {
  if (config.otp.provider === 'mock') {
    console.log('[otp] mock code for', phone, code);
    return;
  }

  const { authKey, templateId, sender } = config.otp.msg91;
  if (!authKey || !templateId) {
    throw new ApiError(503, 'otp_provider_error', 'SMS service is not configured');
  }
  const url = `${MSG91_OTP_URL}?template_id=${encodeURIComponent(templateId)}&mobile=91${phone}&otp=${code}`;
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { authkey: authKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(sender ? { sender } : {}),
    });
  } catch (e) {
    console.error('[otp] msg91 unreachable:', e.message);
    throw new ApiError(503, 'otp_provider_error', 'Could not send the SMS — try again in a minute');
  }
  // MSG91 answers 200 with {"type":"error"} for some failures, so check both.
  const text = await response.text().catch(() => '');
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    /* non-JSON body */
  }
  if (!response.ok || body?.type === 'error') {
    console.error('[otp] msg91 rejected the send:', response.status, text.slice(0, 200));
    throw new ApiError(503, 'otp_provider_error', 'Could not send the SMS — try again in a minute');
  }
}

/**
 * Issues a new code for (phone, purpose): enforces the resend cooldown and the
 * hourly cap, sends the SMS, then records the hash. Returns the send response
 * shape from SPEC §9.1 — with `mock_code` only when the mock provider echoes.
 */
export async function requestOtp(phone, purpose) {
  const { ttlSeconds, resendSeconds, maxSendsPerHour, provider, mockEcho } = config.otp;

  // One query for both throttles; the DB clock decides, never Node's.
  const recent = await one(
    `SELECT count(*)::int AS sends_last_hour,
            EXTRACT(EPOCH FROM (now() - max(created_at)))::int AS seconds_since_last
       FROM otp_codes
      WHERE phone = $1 AND purpose = $2 AND created_at > now() - interval '1 hour'`,
    [phone, purpose],
  );
  if (recent.seconds_since_last !== null && recent.seconds_since_last < resendSeconds) {
    const wait = resendSeconds - recent.seconds_since_last;
    throw new ApiError(429, 'otp_cooldown', `Please wait ${wait} seconds before asking for another code`);
  }
  if (recent.sends_last_hour >= maxSendsPerHour) {
    throw new ApiError(429, 'otp_limit', 'Too many codes requested for this number. Try again in an hour.');
  }

  const code = generateCode();
  await sendOtpSms(phone, code); // throws 503 before anything is stored
  await query(
    `INSERT INTO otp_codes (phone, purpose, code_hash, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(secs => $4))`,
    [phone, purpose, hashOtp(phone, purpose, code), ttlSeconds],
  );

  return {
    sent: true,
    mock: provider === 'mock',
    expires_in: ttlSeconds,
    retry_after: resendSeconds,
    ...(mockEcho ? { mock_code: code } : {}),
  };
}

/**
 * Checks `code` against the LATEST unconsumed code for (phone, purpose) and
 * consumes it. Throws 410 otp_expired (none / expired), 429 too_many_attempts,
 * 400 invalid_otp (and counts the attempt). Resolves true on success.
 */
export async function verifyOtp(phone, purpose, code) {
  const row = await one(
    `SELECT id, code_hash, attempts, (expires_at <= now()) AS expired
       FROM otp_codes
      WHERE phone = $1 AND purpose = $2 AND consumed_at IS NULL
      ORDER BY created_at DESC, id DESC
      LIMIT 1`,
    [phone, purpose],
  );
  if (!row || row.expired) {
    throw new ApiError(410, 'otp_expired', 'Code expired — ask for a new one');
  }
  if (row.attempts >= config.otp.maxAttempts) {
    throw new ApiError(429, 'too_many_attempts', 'Too many wrong codes — ask for a new one');
  }

  const expected = Buffer.from(row.code_hash, 'hex');
  const given = Buffer.from(hashOtp(phone, purpose, String(code)), 'hex');
  const matches = expected.length === given.length && timingSafeEqual(expected, given);
  if (!matches) {
    await query('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1', [row.id]);
    throw new ApiError(400, 'invalid_otp', 'Incorrect code');
  }

  await query('UPDATE otp_codes SET consumed_at = now() WHERE id = $1', [row.id]);
  return true;
}
