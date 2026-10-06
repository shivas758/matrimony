import { Router } from 'express';
import { z } from 'zod';
import { many, one, tx } from '../lib/db.js';
import {
  checkPhoneVerification, hashPassword, signPhoneVerification, signToken, verifyPassword,
} from '../lib/auth.js';
import { asyncHandler, badRequest, conflict, unauthorized } from '../lib/errors.js';
import { parse, passwordSchema, phoneSchema } from '../lib/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { agentPublic } from '../lib/serialize.js';
import { requestOtp, verifyOtp } from '../lib/otp.js';

export const authRouter = Router();

const OTP_PURPOSE = 'agent_signup';

const otpSendSchema = z.object({ phone: phoneSchema });
const otpVerifySchema = z.object({
  phone: phoneSchema,
  code: z.string().trim().regex(/^\d{4,8}$/, 'Enter the 6-digit code'),
});

// POST /api/auth/otp/send {phone} — first step of agent signup (SPEC §9.1).
// A number that is already an agent gets 409 so the app can point to Login.
authRouter.post(
  '/otp/send',
  asyncHandler(async (req, res) => {
    const { phone } = parse(otpSendSchema, req.body ?? {});
    const existing = await one('SELECT id FROM agents WHERE phone = $1', [phone]);
    if (existing) throw conflict('phone_taken', 'This mobile number is already registered');
    res.json(await requestOtp(phone, OTP_PURPOSE));
  }),
);

// POST /api/auth/otp/verify {phone, code} → {verification_token} for /signup.
authRouter.post(
  '/otp/verify',
  asyncHandler(async (req, res) => {
    const { phone, code } = parse(otpVerifySchema, req.body ?? {});
    await verifyOtp(phone, OTP_PURPOSE, code);
    res.json({ verification_token: signPhoneVerification(phone, OTP_PURPOSE) });
  }),
);

const signupSchema = z.object({
  full_name: z.string().trim().min(2, 'Enter your full name').max(120),
  phone: phoneSchema,
  password: passwordSchema,
  agency_name: z.string().trim().max(120).optional().nullable(),
  community_ids: z.array(z.number().int().positive()).min(1, 'Select at least one community'),
  // Proof from /otp/verify (SPEC §9.1). Optional in the schema so a missing
  // token answers phone_not_verified rather than validation_failed.
  phone_verification_token: z.string().optional(),
});

/** Communities the agent belongs to, as {id, name}. */
async function agentCommunities(agentId) {
  return many(
    `SELECT c.id, c.name
       FROM agent_communities ac JOIN communities c ON c.id = ac.community_id
      WHERE ac.agent_id = $1
      ORDER BY c.sort_order, c.name`,
    [agentId],
  );
}

// POST /api/auth/signup — always creates a 'pending' agent (CLAUDE.md rule 2).
authRouter.post(
  '/signup',
  asyncHandler(async (req, res) => {
    const body = parse(signupSchema, req.body);
    if (!checkPhoneVerification(body.phone_verification_token, body.phone, OTP_PURPOSE)) {
      throw badRequest('phone_not_verified', 'Verify your mobile number with the OTP first');
    }

    const existing = await one('SELECT id FROM agents WHERE phone = $1', [body.phone]);
    if (existing) throw conflict('phone_taken', 'This mobile number is already registered');

    const valid = await many(
      'SELECT id FROM communities WHERE id = ANY($1::int[]) AND active = TRUE',
      [body.community_ids],
    );
    if (valid.length !== body.community_ids.length) {
      throw badRequest('invalid_communities', 'One or more selected communities are not available');
    }

    const password_hash = await hashPassword(body.password);
    const agent = await tx(async (client) => {
      const { rows } = await client.query(
        `INSERT INTO agents (full_name, phone, password_hash, agency_name, role, status)
         VALUES ($1, $2, $3, $4, 'agent', 'pending')
         RETURNING id, full_name, phone, agency_name, role, status, created_at`,
        [body.full_name, body.phone, password_hash, body.agency_name || null],
      );
      const created = rows[0];
      await client.query(
        `INSERT INTO agent_communities (agent_id, community_id)
         SELECT $1, unnest($2::int[])`,
        [created.id, body.community_ids],
      );
      return created;
    });

    res.status(201).json({
      token: signToken(agent),
      agent: agentPublic(agent, await agentCommunities(agent.id)),
    });
  }),
);

const loginSchema = z.object({ phone: phoneSchema, password: z.string().min(1, 'Enter your password') });

// POST /api/auth/login — pending agents DO get a token; routes gate them (SPEC §1).
authRouter.post(
  '/login',
  asyncHandler(async (req, res) => {
    const body = parse(loginSchema, req.body);
    const agent = await one(
      `SELECT id, full_name, phone, password_hash, agency_name, role, status, must_change_password, created_at
         FROM agents WHERE phone = $1`,
      [body.phone],
    );
    const ok = agent && (await verifyPassword(body.password, agent.password_hash));
    if (!ok) throw unauthorized('bad_credentials', 'Mobile number or password is incorrect');

    res.json({
      token: signToken(agent),
      agent: agentPublic(agent, await agentCommunities(agent.id)),
    });
  }),
);

const forgotSchema = z.object({ phone: phoneSchema });

// POST /api/auth/forgot-password {phone}
// Files a request an admin sees (name + phone) and settles by handing out a
// temporary password out of band. Always 200 so the endpoint cannot be used
// to probe which numbers are registered.
authRouter.post(
  '/forgot-password',
  asyncHandler(async (req, res) => {
    const { phone } = parse(forgotSchema, req.body);
    const agent = await one('SELECT id FROM agents WHERE phone = $1', [phone]);
    if (agent) {
      await one(
        `INSERT INTO password_reset_requests (agent_id)
         SELECT $1 WHERE NOT EXISTS (
           SELECT 1 FROM password_reset_requests WHERE agent_id = $1 AND status = 'pending')
         RETURNING id`,
        [agent.id],
      );
    }
    res.json({
      ok: true,
      message: 'If this number is registered, the admin has been notified and will contact you with a temporary password.',
    });
  }),
);

// GET /api/auth/me — allowed for pending/suspended so the app can show the right screen.
authRouter.get(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    res.json({ agent: agentPublic(req.agent, await agentCommunities(req.agent.id)) });
  }),
);

const changePasswordSchema = z.object({
  current_password: z.string().min(1, 'Enter your current password'),
  new_password: passwordSchema,
});

// POST /api/auth/change-password (SPEC §5 screen 10)
authRouter.post(
  '/change-password',
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = parse(changePasswordSchema, req.body);
    const row = await one('SELECT password_hash FROM agents WHERE id = $1', [req.agent.id]);
    if (!(await verifyPassword(body.current_password, row.password_hash))) {
      throw unauthorized('bad_credentials', 'Current password is incorrect');
    }
    if (req.agent.must_change_password && body.new_password === body.current_password) {
      throw badRequest('same_password', 'Choose a password different from the temporary one');
    }
    // Clearing the flag is what lets a temporary-password login back into the app.
    await one('UPDATE agents SET password_hash = $1, must_change_password = FALSE WHERE id = $2 RETURNING id', [
      await hashPassword(body.new_password),
      req.agent.id,
    ]);
    res.json({ ok: true });
  }),
);
