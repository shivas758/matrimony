// Firebase phone-auth ID tokens — SPEC §9.19 A.
//
// With OTP_PROVIDER=firebase the app sends and checks the SMS code through
// Firebase Authentication and hands us the resulting ID token. We verify it
// ourselves (no Google SDK), as Firebase documents for third-party backends:
//   * RS256, signed by one of the certificates published at
//     https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com
//     (picked by the token's `kid`; cached for the response's max-age)
//   * aud = project id, iss = https://securetoken.google.com/<project id>
//   * exp in the future, iat / auth_time not in the future, non-empty sub
// plus our own rules: the sign-in is fresh (auth_time within 15 minutes) and
// the token carries the phone number being verified.
import jwt from 'jsonwebtoken';
import { config } from './config.js';
import { ApiError, badRequest } from './errors.js';

const MAX_AUTH_AGE_SECONDS = 15 * 60;
const CLOCK_SKEW_SECONDS = 60;

let certCache = { certs: null, expiresAt: 0 };

/** Test helper: forget cached certificates. */
export function resetFirebaseCertCache() {
  certCache = { certs: null, expiresAt: 0 };
}

async function fetchCerts() {
  let response;
  try {
    response = await fetch(config.firebase.certsUrl);
  } catch (e) {
    console.error('[firebase] certificate fetch failed:', e.message);
    throw new ApiError(503, 'otp_provider_error', 'Could not check the code right now — try again in a minute');
  }
  const body = await response.json().catch(() => null);
  if (!response.ok || !body || typeof body !== 'object') {
    console.error('[firebase] certificate fetch answered', response.status);
    throw new ApiError(503, 'otp_provider_error', 'Could not check the code right now — try again in a minute');
  }
  const maxAge = Number(/max-age=(\d+)/.exec(response.headers.get('cache-control') || '')?.[1] || 0);
  certCache = { certs: body, expiresAt: Date.now() + maxAge * 1000 };
  return body;
}

/** The PEM certificate for `kid`; refetches once when the kid is unknown (key rotation). */
async function certFor(kid) {
  if (certCache.certs && certCache.expiresAt > Date.now() && certCache.certs[kid]) return certCache.certs[kid];
  const certs = await fetchCerts();
  return certs[kid] || null;
}

const invalid = () =>
  badRequest('invalid_firebase_token', 'Phone verification failed — ask for a new code and try again');

/**
 * Verifies a Firebase ID token from a phone sign-in and returns the 10-digit
 * Indian mobile number it proves. Throws 400 invalid_firebase_token,
 * 400 phone_mismatch (when `expectedPhone` differs), 503 otp_provider_error.
 */
export async function verifyFirebasePhoneToken(idToken, expectedPhone) {
  const { projectId } = config.firebase;
  if (!projectId) throw new ApiError(503, 'otp_provider_error', 'Phone verification is not configured');

  const decoded = jwt.decode(String(idToken || ''), { complete: true });
  if (!decoded?.header || decoded.header.alg !== 'RS256' || !decoded.header.kid) throw invalid();

  const cert = await certFor(decoded.header.kid);
  if (!cert) throw invalid();

  let claims;
  try {
    claims = jwt.verify(String(idToken), cert, {
      algorithms: ['RS256'],
      audience: projectId,
      issuer: `https://securetoken.google.com/${projectId}`,
      clockTolerance: CLOCK_SKEW_SECONDS,
    });
  } catch {
    throw invalid();
  }

  const now = Math.floor(Date.now() / 1000);
  const authTime = Number(claims.auth_time);
  if (!claims.sub || typeof claims.sub !== 'string') throw invalid();
  if (!Number.isFinite(authTime) || authTime > now + CLOCK_SKEW_SECONDS) throw invalid();
  if (now - authTime > MAX_AUTH_AGE_SECONDS) throw invalid();
  if (claims.firebase?.sign_in_provider && claims.firebase.sign_in_provider !== 'phone') throw invalid();

  const match = /^\+91(\d{10})$/.exec(String(claims.phone_number || ''));
  if (!match) throw invalid();
  if (expectedPhone && match[1] !== expectedPhone) {
    throw badRequest('phone_mismatch', 'This code was for a different mobile number');
  }
  return match[1];
}
