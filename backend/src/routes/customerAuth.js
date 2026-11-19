// Wedbook Matrimony sign-in — SPEC §9.1 / §9.3-A / §9.9 / §9.24 C. Mounted at
// /api/customer/auth (public; the credential paths are rate-limited in server.js).
// Since v2.14 customers log in with mobile + password; the OTP is used once at
// signup (purpose 'signup') and for "Forgot password?" (purpose 'reset'). An
// OTP call without a purpose is the old login-or-signup flow of apps before
// 3.5.0, kept so they keep working.
import { Router } from 'express';
import { z } from 'zod';
import { one, query } from '../lib/db.js';
import {
  checkPhoneVerification, hashPassword, signCustomerToken, signPhoneVerification, verifyPassword,
} from '../lib/auth.js';
import { asyncHandler, badRequest, conflict, notFound, unauthorized } from '../lib/errors.js';
import { parse, passwordSchema, phoneSchema } from '../lib/validate.js';
import { checkOtp, otpSendSchema, otpVerifySchema, startOtp } from '../lib/otp.js';
import { findCustomerByPhone, loadCustomerMe } from '../lib/customers.js';
import { requireCustomer } from '../middleware/customerAuth.js';

export const customerAuthRouter = Router();

/** Stored OTP purpose of signup codes (and of the old OTP login). */
const PURPOSE = 'customer_login';
/** Stored OTP purpose of "Forgot password?" codes (SPEC §9.24 C). */
const RESET_PURPOSE = 'customer_reset';

/** `purpose` of the OTP routes: 'signup' | 'reset' | absent (the old login). */
const otpPurpose = z.object({ purpose: z.enum(['login', 'signup', 'reset']).optional() });

const phoneTaken = () =>
  conflict('phone_taken', 'This mobile number is already registered — log in with your password');
const noAccount = () => notFound('account_not_found', 'No account with this mobile number');

// POST /api/customer/auth/otp/send {phone, purpose?, firebase?} (SPEC §9.1 / §9.19 A / §9.24 C)
// signup → 409 phone_taken and reset → 404 account_not_found, both before any
// SMS. Without a purpose (apps before 3.5.0) it works for any number.
customerAuthRouter.post(
  '/otp/send',
  asyncHandler(async (req, res) => {
    const body = req.body ?? {};
    const { phone, firebase } = parse(otpSendSchema, body);
    const { purpose } = parse(otpPurpose, body);
    if (purpose === 'signup' && (await findCustomerByPhone(phone))) throw phoneTaken();
    if (purpose === 'reset') {
      if (!(await findCustomerByPhone(phone))) throw noAccount();
      return res.json(await startOtp(phone, RESET_PURPOSE, { app: 'customer', firebase }));
    }
    res.json(await startOtp(phone, PURPOSE, { app: 'customer', firebase }));
  }),
);

// POST /api/customer/auth/otp/verify {phone, code | firebase_id_token, purpose?}
// signup → {verification_token} for /signup; reset → {verification_token} for
// /reset-password. Without a purpose (apps before 3.5.0): an existing customer
// is logged in ({token, customer}), an unknown number gets {new: true,
// verification_token}. Pending/suspended customers still get a token so the
// app can show the right screen (their routes are gated).
customerAuthRouter.post(
  '/otp/verify',
  asyncHandler(async (req, res) => {
    const body = parse(otpVerifySchema, req.body ?? {});
    const { purpose } = parse(otpPurpose, req.body ?? {});
    const { phone } = body;

    if (purpose === 'reset') {
      // Checked before the code so a wrong number never burns an attempt.
      if (!(await findCustomerByPhone(phone))) throw noAccount();
      await checkOtp(phone, RESET_PURPOSE, body);
      return res.json({ verification_token: signPhoneVerification(phone, RESET_PURPOSE) });
    }

    if (purpose === 'signup') {
      if (await findCustomerByPhone(phone)) throw phoneTaken();
      await checkOtp(phone, PURPOSE, body);
      return res.json({ new: true, verification_token: signPhoneVerification(phone, PURPOSE) });
    }

    await checkOtp(phone, PURPOSE, body);
    const customer = await findCustomerByPhone(phone);

    if (!customer) {
      return res.json({ new: true, verification_token: signPhoneVerification(phone, PURPOSE) });
    }
    // A form-registered customer (SPEC §9.3-B) has phone_verified_at = null
    // until this first OTP login.
    await query(
      `UPDATE customers
          SET phone_verified_at = COALESCE(phone_verified_at, now()), last_login_at = now()
        WHERE id = $1`,
      [customer.id],
    );
    res.json({ token: signCustomerToken(customer), customer: await loadCustomerMe(customer.id) });
  }),
);

const loginSchema = z.object({ phone: phoneSchema, password: z.string().min(1, 'Enter your password') });

// POST /api/customer/auth/login {phone, password} → {token, customer} (SPEC §9.24 C).
// 409 password_not_set for a customer without a password (the web form, apps
// before 3.5.0) — the app sends them through "Forgot password?".
customerAuthRouter.post(
  '/login',
  asyncHandler(async (req, res) => {
    const body = parse(loginSchema, req.body ?? {});
    const row = await one('SELECT id, password_hash FROM customers WHERE phone = $1', [body.phone]);
    if (row && !row.password_hash) {
      throw conflict('password_not_set', "Set a password for this number first — we'll send you a code");
    }
    const ok = row && (await verifyPassword(body.password, row.password_hash));
    if (!ok) throw unauthorized('bad_credentials', 'Mobile number or password is incorrect');
    await query('UPDATE customers SET last_login_at = now() WHERE id = $1', [row.id]);
    res.json({ token: signCustomerToken(row), customer: await loadCustomerMe(row.id) });
  }),
);

const signupSchema = z.object({
  full_name: z.string().trim().min(2, 'Enter your full name').max(120),
  phone: phoneSchema,
  // Required by the 3.5.0 app (SPEC §9.24 C); older builds sign up without one
  // and set it later through "Forgot password?".
  password: passwordSchema.optional(),
  // v1.0 app sends it (account starts pending with that agent); v1.1 signs up
  // as a guest and links an agent later (SPEC §9.12).
  agent_phone: z.preprocess((v) => (v === '' || v === null ? undefined : v), phoneSchema.optional()),
  // Optional in the schema so a missing token gets the specific
  // phone_not_verified code (SPEC §9.1) rather than validation_failed.
  phone_verification_token: z.string().optional(),
  // The 3.3.0 app requires the terms checkbox (SPEC §9.22 C); older builds omit it.
  accepted_terms: z.boolean().optional(),
});

// POST /api/customer/auth/signup — a 'guest' with no agent (SPEC §9.12), or,
// with agent_phone (v1.0 app), a 'pending' customer attached to that ACTIVE
// agent, who approves from Mediator → Clients (SPEC §9.3-A).
customerAuthRouter.post(
  '/signup',
  asyncHandler(async (req, res) => {
    const body = parse(signupSchema, req.body ?? {});
    if (!checkPhoneVerification(body.phone_verification_token, body.phone, PURPOSE)) {
      throw badRequest('phone_not_verified', 'Verify your mobile number with the OTP first');
    }

    if (await findCustomerByPhone(body.phone)) throw phoneTaken();

    let agent = null;
    if (body.agent_phone) {
      agent = await one('SELECT id, status FROM agents WHERE phone = $1 AND NOT is_demo', [body.agent_phone]);
      if (!agent) throw notFound('agent_not_found', 'No agent has this mobile number — check with your agent');
      if (agent.status !== 'active') {
        throw badRequest('agent_not_active', "Your agent's account is not active yet — check with your agent");
      }
    }

    const passwordHash = body.password ? await hashPassword(body.password) : null;
    let created;
    try {
      created = await one(
        `INSERT INTO customers (full_name, phone, agent_id, status, source, phone_verified_at, terms_accepted_at,
                                password_hash, password_set_at)
         VALUES ($1, $2, $3, $4, 'app', now(), CASE WHEN $5 THEN now() END,
                 $6::text, CASE WHEN $6::text IS NOT NULL THEN now() END)
         RETURNING id`,
        [body.full_name, body.phone, agent?.id ?? null, agent ? 'pending' : 'guest', body.accepted_terms === true,
          passwordHash],
      );
    } catch (e) {
      // Two signups for the same number racing past the check above.
      if (e.code === '23505') throw phoneTaken();
      throw e;
    }

    res.status(201).json({
      token: signCustomerToken(created),
      customer: await loadCustomerMe(created.id),
    });
  }),
);

const resetSchema = z.object({
  phone: phoneSchema,
  phone_verification_token: z.string().optional(),
  new_password: passwordSchema,
});

// POST /api/customer/auth/reset-password {phone, phone_verification_token, new_password}
// → {token, customer}: "Forgot password?" after the reset OTP (SPEC §9.24 C).
customerAuthRouter.post(
  '/reset-password',
  asyncHandler(async (req, res) => {
    const body = parse(resetSchema, req.body ?? {});
    if (!checkPhoneVerification(body.phone_verification_token, body.phone, RESET_PURPOSE)) {
      throw badRequest('phone_not_verified', 'Verify your mobile number with the OTP first');
    }
    const row = await one(
      `UPDATE customers
          SET password_hash = $2, password_set_at = now(), last_login_at = now(),
              phone_verified_at = COALESCE(phone_verified_at, now()), updated_at = now()
        WHERE phone = $1
        RETURNING id`,
      [body.phone, await hashPassword(body.new_password)],
    );
    if (!row) throw noAccount();
    res.json({ token: signCustomerToken(row), customer: await loadCustomerMe(row.id) });
  }),
);

const changePasswordSchema = z.object({
  current_password: z.string().optional(),
  new_password: passwordSchema,
});

// POST /api/customer/auth/change-password {current_password?, new_password} → {ok: true}.
// current_password is needed only when the account already has a password.
customerAuthRouter.post(
  '/change-password',
  requireCustomer,
  asyncHandler(async (req, res) => {
    const body = parse(changePasswordSchema, req.body ?? {});
    const row = await one('SELECT password_hash FROM customers WHERE id = $1', [req.customer.id]);
    if (row.password_hash) {
      if (!body.current_password) throw badRequest('validation_failed', 'Enter your current password');
      if (!(await verifyPassword(body.current_password, row.password_hash))) {
        throw unauthorized('bad_credentials', 'Current password is incorrect');
      }
    }
    await query(
      'UPDATE customers SET password_hash = $2, password_set_at = now(), updated_at = now() WHERE id = $1',
      [req.customer.id, await hashPassword(body.new_password)],
    );
    res.json({ ok: true });
  }),
);

// GET /api/customer/auth/me — allowed while pending / rejected / suspended so
// the app can show the waiting (or blocked) screen.
customerAuthRouter.get(
  '/me',
  requireCustomer,
  asyncHandler(async (req, res) => {
    res.json({ customer: await loadCustomerMe(req.customer.id) });
  }),
);
