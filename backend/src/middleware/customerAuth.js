import { many, one } from '../lib/db.js';
import { verifyToken } from '../lib/auth.js';
import { forbidden, unauthorized } from '../lib/errors.js';
import { customerAccessLevel } from '../lib/customers.js';
import { bearerToken } from './auth.js';

/**
 * Resolves a Gandharva bearer token (SPEC §9.2, `typ: 'customer'`) to
 * req.customer = { ...customer row, agent, community_ids }. `community_ids`
 * are the customer's AGENT's communities — the customer browses those
 * (customerVisibilityClause in lib/profiles.js). Agent tokens are refused
 * here, exactly as requireAuth refuses customer tokens.
 */
export async function requireCustomer(req, _res, next) {
  try {
    const token = bearerToken(req);
    if (!token) throw unauthorized('missing_token', 'Sign in to continue');

    let payload;
    try {
      payload = verifyToken(token);
    } catch {
      throw unauthorized('invalid_token', 'Session expired, please sign in again');
    }
    if (payload.typ !== 'customer') throw unauthorized('invalid_token', 'Sign in with a Gandharva account');

    const customer = await one(
      `SELECT id, full_name, phone, agent_id, status, source, phone_verified_at,
              approved_by, approved_at, last_login_at, created_at
         FROM customers WHERE id = $1`,
      [Number(payload.sub)],
    );
    if (!customer) throw unauthorized('unknown_customer', 'Account no longer exists');

    const [agent, rows] = await Promise.all([
      one('SELECT id, full_name, agency_name, phone, city, status FROM agents WHERE id = $1', [customer.agent_id]),
      many('SELECT community_id FROM agent_communities WHERE agent_id = $1', [customer.agent_id]),
    ]);
    req.customer = { ...customer, agent, community_ids: rows.map((r) => r.community_id) };
    next();
  } catch (e) {
    next(e);
  }
}

/**
 * Blocks everything a pending / rejected / suspended customer may not do
 * (SPEC §9.2: they can log in, see the waiting screen and fill their profile).
 */
export function requireActiveCustomer(req, _res, next) {
  const { status } = req.customer;
  if (status === 'active') return next();
  if (status === 'guest') {
    return next(forbidden('agent_required', 'Choose your agent first'));
  }
  if (status === 'pending') {
    return next(forbidden('account_pending', 'Your agent has not approved your account yet'));
  }
  if (status === 'rejected') {
    return next(forbidden('account_rejected', 'Your agent did not approve this account'));
  }
  return next(forbidden('account_suspended', 'Your account has been suspended'));
}

/** Everything except a suspended account — guest browsing (SPEC §9.12). */
export function requireNotSuspended(req, _res, next) {
  if (req.customer.status === 'suspended') {
    return next(forbidden('account_suspended', 'Your account has been suspended'));
  }
  return next();
}

/**
 * Full access (SPEC §9.12): active AND at least one paid profile. Sets
 * req.customer.access. 403 unlock_required otherwise (suspended keeps its own code).
 */
export async function requireFullAccess(req, _res, next) {
  try {
    if (req.customer.status === 'suspended') {
      throw forbidden('account_suspended', 'Your account has been suspended');
    }
    req.customer.access = await customerAccessLevel(req.customer);
    if (req.customer.access !== 'full') {
      throw forbidden(
        'unlock_required',
        'Register your profile, pay the registration fee and get approved by your agent to open profiles',
      );
    }
    next();
  } catch (e) {
    next(e);
  }
}
