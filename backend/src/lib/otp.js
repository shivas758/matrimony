// One-time codes for agent signup and customer login — SPEC §9.1.
//
// The code itself is never stored: otp_codes keeps sha256(secret|phone|purpose|code),
// an expiry, an attempt counter and consumed_at (a code is verified once).
// Per (phone, purpose): OTP_RESEND_SECONDS between sends, OTP_MAX_SENDS_PER_HOUR
// sends per hour, OTP_MAX_ATTEMPTS wrong guesses per code.
//
// Switching from mock to production (no code change — see .env.example):
//   OTP_PROVIDER=startmessaging   (the owner's choice, SPEC §9.19 C2)
//   STARTMESSAGING_API_KEY=sm_live_...  STARTMESSAGING_TEMPLATE_ID=<OTP template id>
// or
//   OTP_PROVIDER=fast2sms      (SPEC §9.19 C — needs Fast2SMS website verification)
//   FAST2SMS_API_KEY=<Dev API key; the account needs KYC + a first ₹100 recharge>
// or
//   OTP_PROVIDER=msg91
//   MSG91_AUTH_KEY=<your MSG91 auth key>
//   MSG91_TEMPLATE_ID=<the DLT-approved OTP template id>
//   MSG91_SENDER=<6-char sender id, optional>
//   OTP_MOCK_ECHO is ignored for a real provider (never echoed).
// or, Firebase phone auth (SPEC §9.19 A — the phone does the SMS, we verify
// the Firebase ID token; no code is generated or stored here):
//   OTP_PROVIDER=firebase + FIREBASE_PROJECT_ID / _API_KEY / _SENDER_ID /
//   _APP_ID_AGENT / _APP_ID_CUSTOMER
// then restart the API. In mock mode nothing is sent: generateCode() always
// returns OTP_MOCK_CODE (default 123456) and the send response echoes it as
// `mock_code` when OTP_MOCK_ECHO=true so the apps can show "Test mode".

import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { config } from './config.js';
import { one, query } from './db.js';
import { ApiError, badRequest } from './errors.js';
import { verifyFirebasePhoneToken } from './firebaseAuth.js';
import { phoneSchema } from './validate.js';

const MSG91_OTP_URL = 'https://control.msg91.com/api/v5/otp';

/** sha256 hex of secret|phone|purpose|code — what otp_codes.code_hash holds. */
export function hashOtp(phone, purpose, code) {
  return createHash('sha256')
    .update(`${config.jwtSecret}|${phone}|${purpose}|${code}`)
    .digest('hex');
}

/** True for the reviewers' number on the customer login (SPEC §9.19 F). */
export function isReviewLogin(phone, purpose) {
  const { phone: reviewPhone, code } = config.otp.review;
  return Boolean(reviewPhone && code && purpose === 'customer_login' && phone === reviewPhone);
}

/** A 6-digit code. Mock provider: always OTP_MOCK_CODE, so testers know it. */
export function generateCode() {
  if (config.otp.provider === 'mock') return config.otp.mockCode;
  return String(randomInt(0, 1_000_000)).padStart(6, '0');
}

const smsFailed = () => new ApiError(503, 'otp_provider_error', 'Could not send the SMS — try again in a minute');

/**
 * Fast2SMS bulkV2 OTP route (SPEC §9.19 C): our own numeric code, Fast2SMS's
 * DLT-registered OTP text. Success is HTTP 200 with `return: true`.
 */
async function sendViaFast2sms(phone, code) {
  const { apiKey, url } = config.otp.fast2sms;
  if (!apiKey) throw new ApiError(503, 'otp_provider_error', 'SMS service is not configured');
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { authorization: apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ route: 'otp', variables_values: code, numbers: phone, flash: 0 }),
    });
  } catch (e) {
    console.error('[otp] fast2sms unreachable:', e.message);
    throw smsFailed();
  }
  const text = await response.text().catch(() => '');
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    /* non-JSON body */
  }
  if (!response.ok || body?.return !== true) {
    // e.g. 412 bad key, 416 no balance, 996 KYC pending, 999 first ₹100 recharge missing.
    console.error('[otp] fast2sms rejected the send:', response.status, text.slice(0, 200));
    throw smsFailed();
  }
}

/**
 * StartMessaging (SPEC §9.19 C2): our own code through their pre-approved OTP
 * template and shared sender — no DLT of our own. Success = 2xx + success: true.
 */
async function sendViaStartMessaging(phone, code) {
  const { apiKey, templateId, appName, url } = config.otp.startmessaging;
  if (!apiKey || !templateId) throw new ApiError(503, 'otp_provider_error', 'SMS service is not configured');
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'X-API-Key': apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ phoneNumber: `+91${phone}`, templateId, variables: { otp: code, appName } }),
    });
  } catch (e) {
    console.error('[otp] startmessaging unreachable:', e.message);
    throw smsFailed();
  }
  const text = await response.text().catch(() => '');
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    /* non-JSON body */
  }
  if (!response.ok || body?.success !== true) {
    console.error('[otp] startmessaging rejected the send:', response.status, text.slice(0, 300));
    throw smsFailed();
  }
}

/**
 * Delivers `code` to `phone`. mock → console only. startmessaging / fast2sms /
 * msg91 → their APIs with our own code (the verify logic stays identical for
 * every provider). Any provider problem is a 503 otp_provider_error — nothing
 * is stored then.
 */
export async function sendOtpSms(phone, code) {
  if (config.otp.provider === 'mock') {
    console.log('[otp] mock code for', phone, code);
    return;
  }
  if (config.otp.provider === 'startmessaging') return sendViaStartMessaging(phone, code);
  if (config.otp.provider === 'fast2sms') return sendViaFast2sms(phone, code);

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
    throw smsFailed();
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
    throw smsFailed();
  }
}

/**
 * Issues a new code for (phone, purpose): enforces the resend cooldown and the
 * hourly cap, sends the SMS, then records the hash. Returns the send response
 * shape from SPEC §9.1 — with `mock_code` only when the mock provider echoes.
 */
export async function requestOtp(phone, purpose) {
  const { ttlSeconds, resendSeconds, maxSendsPerHour, mockEcho } = config.otp;
  const review = isReviewLogin(phone, purpose);
  const provider = review ? 'review' : config.otp.provider;

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

  // The reviewers' number gets its fixed code and no SMS (SPEC §9.19 F).
  const code = review ? config.otp.review.code : generateCode();
  if (!review) await sendOtpSms(phone, code); // throws 503 before anything is stored
  await query(
    `INSERT INTO otp_codes (phone, purpose, code_hash, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(secs => $4))`,
    [phone, purpose, hashOtp(phone, purpose, code), ttlSeconds],
  );

  return {
    sent: true,
    provider,
    mock: provider === 'mock',
    expires_in: ttlSeconds,
    retry_after: resendSeconds,
    ...(mockEcho && !review ? { mock_code: code } : {}),
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

// ---- Provider-independent entry points used by both auth routers ----------

/** Body of POST …/otp/send. `firebase: true` = "this app can do Firebase OTP" (§9.19 A). */
export const otpSendSchema = z.object({ phone: phoneSchema, firebase: z.boolean().optional() });

/** Body of POST …/otp/verify: a typed `code` (mock / msg91) or a `firebase_id_token`. */
export const otpVerifySchema = z
  .object({
    phone: phoneSchema,
    code: z.string().trim().regex(/^\d{4,8}$/, 'Enter the 6-digit code').optional(),
    firebase_id_token: z.string().trim().min(20).max(8192).optional(),
  })
  .refine((b) => b.code || b.firebase_id_token, { message: 'Enter the 6-digit code', path: ['code'] });

/**
 * Public Firebase client options for the agent app ('agent') or the customer
 * app ('customer'), or null when any of them is missing.
 */
export function firebaseClientOptions(app) {
  const f = config.firebase;
  const appId = app === 'customer' ? f.appIdCustomer : f.appIdAgent;
  if (!f.projectId || !f.apiKey || !f.senderId || !appId) return null;
  return { api_key: f.apiKey, app_id: appId, messaging_sender_id: f.senderId, project_id: f.projectId };
}

/**
 * The send step. mock / msg91 → requestOtp (we send the code). firebase → no
 * SMS from us: the app gets the Firebase options and verifies the number
 * itself; an app that cannot do that is told to update (426).
 */
export async function startOtp(phone, purpose, { app, firebase = false }) {
  const { provider, ttlSeconds, resendSeconds } = config.otp;
  if (provider !== 'firebase' || isReviewLogin(phone, purpose)) return requestOtp(phone, purpose);

  if (!firebase) throw new ApiError(426, 'app_update_required', 'Please update the app to get your code');
  const options = firebaseClientOptions(app);
  if (!options) throw new ApiError(503, 'otp_provider_error', 'Phone verification is not configured yet');
  return {
    sent: false,
    provider: 'firebase',
    mock: false,
    expires_in: ttlSeconds,
    retry_after: resendSeconds,
    firebase: options,
  };
}

/**
 * The verify step: a typed code for mock / msg91, a Firebase ID token for
 * firebase (§9.19 A). Sending the wrong kind is 400 otp_provider_mismatch.
 * Resolves true when `phone` is proven.
 */
export async function checkOtp(phone, purpose, { code, firebase_id_token: idToken }) {
  if (config.otp.provider === 'firebase' && !isReviewLogin(phone, purpose)) {
    if (!idToken) throw badRequest('otp_provider_mismatch', 'Please update the app to verify your number');
    await verifyFirebasePhoneToken(idToken, phone);
    return true;
  }
  if (idToken || !code) throw badRequest('otp_provider_mismatch', 'Enter the 6-digit code sent to your phone');
  return verifyOtp(phone, purpose, code);
}
