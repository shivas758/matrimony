import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { config } from './config.js';

export const hashPassword = (plain) => bcrypt.hash(plain, config.bcryptRounds);
export const verifyPassword = (plain, hash) => bcrypt.compare(plain, hash);

/** Agent / admin session token. `typ` is absent — see verifyToken. */
export function signToken(agent) {
  return jwt.sign(
    { sub: String(agent.id), role: agent.role },
    config.jwtSecret,
    { expiresIn: config.jwtExpiresIn },
  );
}

/**
 * Customer (Gandharva) session token — SPEC §9.2. The `typ` claim keeps the
 * two audiences apart: agent routes refuse customer tokens and vice versa.
 */
export function signCustomerToken(customer) {
  return jwt.sign(
    { sub: String(customer.id), typ: 'customer' },
    config.jwtSecret,
    { expiresIn: config.jwtExpiresIn },
  );
}

export function verifyToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

/**
 * Short-lived proof that an OTP for `phone` was entered correctly (SPEC §9.1).
 * The signup routes require it before creating an account.
 */
export function signPhoneVerification(phone, purpose) {
  return jwt.sign(
    { typ: 'phone_verification', phone, purpose },
    config.jwtSecret,
    { expiresIn: config.otp.verificationTokenTtl },
  );
}

/** Returns true iff `token` proves `phone` for `purpose` and has not expired. */
export function checkPhoneVerification(token, phone, purpose) {
  try {
    const payload = jwt.verify(String(token || ''), config.jwtSecret);
    return payload.typ === 'phone_verification' && payload.phone === phone && payload.purpose === purpose;
  } catch {
    return false;
  }
}
