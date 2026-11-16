// Approved agents (SPEC §9.23 A). An agent works from signup, but sees only
// their own uploads and clients — and is not listed for customers — until they
// are *approved*: automatically the first time they have APPROVAL_CLIENTS live
// clients, or by an admin. Once approved, always approved.
import { config } from './config.js';
import { query } from './db.js';

/**
 * SQL for the number of LIVE clients of the agent `agentRef` (a column or a
 * `$n`): customers of that agent who are active and whose profile is paid
 * (app, cash or gift code) and not hidden — i.e. published.
 */
export const liveClientsSql = (agentRef) => `(SELECT count(*)::int FROM customers lcu
   WHERE lcu.agent_id = ${agentRef} AND lcu.status = 'active'
     AND EXISTS (SELECT 1 FROM profiles lcp
                  WHERE lcp.customer_id = lcu.id AND lcp.paid_at IS NOT NULL AND lcp.status <> 'hidden'))`;

/** SQL: the agent aliased `a` counts as approved (admins always do). */
export const approvedSql = (alias = 'a') =>
  `(${alias}.role = 'admin' OR ${alias}.approved_at IS NOT NULL OR ${liveClientsSql(`${alias}.id`)} >= ${Number(
    config.agents.approvalClients,
  )})`;

/** True for admins and approved agents. Needs `role` (or `is_admin`) and `approved_at`. */
export function isApproved(agent) {
  return Boolean(agent?.is_admin || agent?.role === 'admin' || agent?.approved_at);
}

/**
 * Stamps `approved_at` when the agent has reached the threshold (and is not
 * approved yet). Runs on `client` (a transaction) when given. Returns the new
 * stamp, or null when nothing changed. Never throws for a missing agent.
 */
export async function refreshAgentApproval(agentId, client = null) {
  if (!agentId) return null;
  const run = client ? (t, p) => client.query(t, p) : query;
  const { rows } = await run(
    `UPDATE agents a SET approved_at = now()
      WHERE a.id = $1 AND a.approved_at IS NULL AND ${liveClientsSql('a.id')} >= $2
      RETURNING approved_at`,
    [agentId, config.agents.approvalClients],
  );
  return rows[0]?.approved_at ?? null;
}

/** refreshAgentApproval for the agent of a customer / the uploader of a profile. */
export async function refreshApprovalForCustomer(customerId) {
  if (!customerId) return null;
  const { rows } = await query('SELECT agent_id FROM customers WHERE id = $1', [customerId]);
  return refreshAgentApproval(rows[0]?.agent_id ?? null);
}

export async function refreshApprovalForProfile(profileId) {
  if (!profileId) return null;
  const { rows } = await query('SELECT uploaded_by FROM profiles WHERE id = $1', [profileId]);
  return refreshAgentApproval(rows[0]?.uploaded_by ?? null);
}
