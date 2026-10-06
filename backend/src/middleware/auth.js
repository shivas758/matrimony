import { many, one } from '../lib/db.js';
import { verifyToken } from '../lib/auth.js';
import { forbidden, unauthorized } from '../lib/errors.js';

/** Bearer token from the Authorization header, or null. */
export function bearerToken(req) {
  const header = req.headers.authorization || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : null;
}

/**
 * Resolves the bearer token to req.agent, including the agent's community ids
 * (used everywhere for visibility filtering — CLAUDE.md rule 1).
 * Customer tokens (SPEC §9.2, `typ: 'customer'`) are refused here: customers
 * have their own routes under /api/customer.
 */
export async function requireAuth(req, _res, next) {
  try {
    const token = bearerToken(req);
    if (!token) throw unauthorized('missing_token', 'Sign in to continue');

    let payload;
    try {
      payload = verifyToken(token);
    } catch {
      throw unauthorized('invalid_token', 'Session expired, please sign in again');
    }
    if (payload.typ) throw unauthorized('invalid_token', 'Sign in with an agent account');

    const agent = await one(
      `SELECT id, full_name, phone, agency_name, role, status, must_change_password, city,
              registration_token, created_at
         FROM agents WHERE id = $1`,
      [Number(payload.sub)],
    );
    if (!agent) throw unauthorized('unknown_agent', 'Account no longer exists');

    const rows = await many('SELECT community_id FROM agent_communities WHERE agent_id = $1', [agent.id]);
    agent.community_ids = rows.map((r) => r.community_id);
    agent.is_admin = agent.role === 'admin';
    req.agent = agent;
    next();
  } catch (e) {
    next(e);
  }
}

/**
 * Blocks pending/suspended agents from everything except /auth/me — and agents
 * holding a temporary password until they set their own (/auth/change-password).
 */
export function requireActive(req, _res, next) {
  const { status, must_change_password } = req.agent;
  if (must_change_password) {
    return next(forbidden('password_change_required', 'Set a new password to continue'));
  }
  if (status === 'active') return next();
  if (status === 'pending') {
    return next(forbidden('account_pending', 'Your account is awaiting admin approval'));
  }
  return next(forbidden('account_suspended', 'Your account has been suspended'));
}

export function requireAdmin(req, _res, next) {
  if (!req.agent.is_admin) return next(forbidden('admin_only', 'Admins only'));
  next();
}

/** Sets req.agent when a valid agent token is present; never rejects. */
export async function optionalAuth(req, res, next) {
  if (!req.headers.authorization) return next();
  requireAuth(req, res, (err) => next(err && err.status === 401 ? undefined : err));
}
