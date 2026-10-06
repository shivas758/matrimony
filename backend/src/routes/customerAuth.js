// Gandharva sign-in — SPEC §9.1 / §9.3-A / §9.9. Mounted at /api/customer/auth
// (public; the OTP and signup paths are rate-limited in server.js).
// Customers have no password: every login is phone + OTP. A verified number
// that is not yet a customer gets a short-lived verification token, which
// /signup must present.
import { Router } from 'express';
import { z } from 'zod';
import { one, query } from '../lib/db.js';
import { checkPhoneVerification, signCustomerToken, signPhoneVerification } from '../lib/auth.js';
import { asyncHandler, badRequest, conflict, notFound } from '../lib/errors.js';
import { parse, phoneSchema } from '../lib/validate.js';
import { requestOtp, verifyOtp } from '../lib/otp.js';
import { findCustomerByPhone, loadCustomerMe } from '../lib/customers.js';
import { requireCustomer } from '../middleware/customerAuth.js';

export const customerAuthRouter = Router();

const PURPOSE = 'customer_login';

const sendSchema = z.object({ phone: phoneSchema });
const verifySchema = z.object({
  phone: phoneSchema,
  code: z.string().trim().regex(/^\d{4,8}$/, 'Enter the 6-digit code'),
});

// POST /api/customer/auth/otp/send {phone}
// Works for any number — the response never says whether it is registered.
customerAuthRouter.post(
  '/otp/send',
  asyncHandler(async (req, res) => {
    const { phone } = parse(sendSchema, req.body ?? {});
    res.json(await requestOtp(phone, PURPOSE));
  }),
);

// POST /api/customer/auth/otp/verify {phone, code}
// Existing customer → login ({token, customer}); unknown number → {new: true,
// verification_token} for /signup. Pending/suspended customers still get a
// token so the app can show the right screen (their routes are gated).
customerAuthRouter.post(
  '/otp/verify',
  asyncHandler(async (req, res) => {
    const { phone, code } = parse(verifySchema, req.body ?? {});
    await verifyOtp(phone, PURPOSE, code);

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

const signupSchema = z.object({
  full_name: z.string().trim().min(2, 'Enter your full name').max(120),
  phone: phoneSchema,
  // v1.0 app sends it (account starts pending with that agent); v1.1 signs up
  // as a guest and links an agent later (SPEC §9.12).
  agent_phone: z.preprocess((v) => (v === '' || v === null ? undefined : v), phoneSchema.optional()),
  // Optional in the schema so a missing token gets the specific
  // phone_not_verified code (SPEC §9.1) rather than validation_failed.
  phone_verification_token: z.string().optional(),
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

    if (await findCustomerByPhone(body.phone)) {
      throw conflict('phone_taken', 'This mobile number is already registered — log in instead');
    }

    let agent = null;
    if (body.agent_phone) {
      agent = await one('SELECT id, status FROM agents WHERE phone = $1', [body.agent_phone]);
      if (!agent) throw notFound('agent_not_found', 'No agent has this mobile number — check with your agent');
      if (agent.status !== 'active') {
        throw badRequest('agent_not_active', "Your agent's account is not active yet — check with your agent");
      }
    }

    let created;
    try {
      created = await one(
        `INSERT INTO customers (full_name, phone, agent_id, status, source, phone_verified_at)
         VALUES ($1, $2, $3, $4, 'app', now())
         RETURNING id`,
        [body.full_name, body.phone, agent?.id ?? null, agent ? 'pending' : 'guest'],
      );
    } catch (e) {
      // Two signups for the same number racing past the check above.
      if (e.code === '23505') throw conflict('phone_taken', 'This mobile number is already registered — log in instead');
      throw e;
    }

    res.status(201).json({
      token: signCustomerToken(created),
      customer: await loadCustomerMe(created.id),
    });
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
