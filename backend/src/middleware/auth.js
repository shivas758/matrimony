import { many, one } from '../lib/db.js';
import { verifyToken } from '../lib/auth.js';
import { forbidden, unauthorized } from '../lib/errors.js';
import { AGENT_SELECT } from '../lib/serialize.js';
import { config } from '../lib/config.js';
import { refreshAgentApproval } from '../lib/agentApproval.js';

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

    const agent = await one(`${AGENT_SELECT} WHERE a.id = $1`, [Number(payload.sub)]);
    if (!agent) throw unauthorized('unknown_agent', 'Account no longer exists');

    const [rows, flags] = await Promise.all([
      many('SELECT community_id FROM agent_communities WHERE agent_id = $1', [agent.id]),
      one('SELECT is_demo FROM agents WHERE id = $1', [agent.id]),
    ]);
    agent.community_ids = rows.map((r) => r.community_id);
    // Store-review demo world (SPEC §9.21).
    agent.is_demo = Boolean(flags?.is_demo);
    agent.is_admin = agent.role === 'admin';
    // SPEC §9.23 A: the approval is stamped the first time the threshold is met
    // (also checked where clients' profiles go live; this is the safety net).
    if (!agent.is_admin && !agent.approved_at && agent.live_clients >= config.agents.approvalClients) {
      agent.approved_at = (await refreshAgentApproval(agent.id)) ?? agent.approved_at;
    }
    agent.approved = agent.is_admin || agent.approved_at != null;
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
