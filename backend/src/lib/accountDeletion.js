// Account deletion requests — SPEC §9.20 F (Google Play's account-deletion rule).
//
// Anyone can ask from the public page /delete-account (both apps link to it);
// an admin confirms with the person (the request is not authenticated — never
// act on it blindly) and completes it here:
//   customer → their profile(s) and photos are deleted, then the account row
//              (payments keep only the amount, for the accounts).
//   agent    → refused while they still own profiles or clients (reassign or
//              delete those first); otherwise the personal data is scrubbed in
//              place — name, phone, password, agency, communities, devices — and
//              the account is suspended. The row stays because history rows
//              point at it and agent codes are never reused (CLAUDE.md rule 8).
import { randomBytes } from 'node:crypto';
import { many, one, query, tx } from './db.js';
import { hashPassword } from './auth.js';
import { badRequest, conflict, notFound } from './errors.js';
import { deleteProfile } from './profiles.js';

export async function createDeletionRequest({ app, phone, fullName = null, reason = null }) {
  // One open request per number and app is enough.
  const open = await one(
    `SELECT id FROM account_deletion_requests WHERE app = $1 AND phone = $2 AND status = 'pending'`,
    [app, phone],
  );
  if (open) return open;
  return one(
    `INSERT INTO account_deletion_requests (app, phone, full_name, reason) VALUES ($1, $2, $3, $4) RETURNING id`,
    [app, phone, fullName, reason],
  );
}

/** Admin list, newest first, with whether a matching account exists. */
export async function listDeletionRequests(status) {
  const rows = await many(
    `SELECT r.*,
            CASE r.app WHEN 'customer' THEN (SELECT id FROM customers WHERE phone = r.phone)
                       ELSE (SELECT id FROM agents WHERE phone = r.phone) END AS account_id
       FROM account_deletion_requests r
      ${status === 'all' ? '' : 'WHERE r.status = $1'}
      ORDER BY CASE WHEN r.status = 'pending' THEN 0 ELSE 1 END, r.created_at DESC
      LIMIT 200`,
    status === 'all' ? [] : [status],
  );
  return rows.map((r) => ({
    id: r.id,
    app: r.app,
    phone: r.phone,
    full_name: r.full_name,
    reason: r.reason,
    status: r.status,
    note: r.note,
    created_at: r.created_at,
    handled_at: r.handled_at,
    account_exists: r.account_id != null,
  }));
}

async function deleteCustomerAccount(customerId) {
  const profiles = await many('SELECT id FROM profiles WHERE customer_id = $1', [customerId]);
  for (const p of profiles) await deleteProfile(p.id);
  await query('DELETE FROM customers WHERE id = $1', [customerId]);
}

async function scrubAgentAccount(agent) {
  if (agent.role === 'admin') throw badRequest('cannot_delete_admin', 'Admin accounts are not deleted this way');
  const owns = await one(
    `SELECT (SELECT count(*) FROM profiles WHERE uploaded_by = $1)::int AS profiles,
            (SELECT count(*) FROM customers WHERE agent_id = $1)::int AS clients`,
    [agent.id],
  );
  if (owns.profiles > 0 || owns.clients > 0) {
    throw conflict(
      'agent_has_data',
      `This agent still has ${owns.profiles} profile(s) and ${owns.clients} client(s) — reassign or delete them first`,
    );
  }
  const unusable = await hashPassword(randomBytes(24).toString('hex'));
  await tx(async (client) => {
    await client.query(
      `UPDATE agents SET full_name = 'Deleted account', phone = $2, password_hash = $3, agency_name = NULL,
              city = NULL, status = 'suspended', must_change_password = FALSE, registration_token = NULL
        WHERE id = $1`,
      [agent.id, `deleted-${agent.id}`, unusable],
    );
    await client.query('DELETE FROM agent_communities WHERE agent_id = $1', [agent.id]);
    await client.query('DELETE FROM push_devices WHERE agent_id = $1', [agent.id]);
    await client.query(`DELETE FROM community_change_requests WHERE agent_id = $1 AND status = 'pending'`, [agent.id]);
  });
}

/** Admin: carry out a pending request (after confirming with the person). */
export async function completeDeletionRequest(id, adminId) {
  const r = await one('SELECT * FROM account_deletion_requests WHERE id = $1', [id]);
  if (!r) throw notFound('request_not_found', 'Request not found');
  if (r.status !== 'pending') throw conflict('already_decided', `This request is already ${r.status}`);

  let note;
  if (r.app === 'customer') {
    const customer = await one('SELECT id FROM customers WHERE phone = $1', [r.phone]);
    if (customer) {
      await deleteCustomerAccount(customer.id);
      note = 'Customer account, profile and photos deleted';
    } else note = 'No customer account with this number';
  } else {
    const agent = await one('SELECT id, role FROM agents WHERE phone = $1', [r.phone]);
    if (agent) {
      await scrubAgentAccount(agent);
      note = 'Agent personal data deleted, account closed';
    } else note = 'No agent account with this number';
  }
  return one(
    `UPDATE account_deletion_requests SET status = 'done', handled_by = $2, handled_at = now(), note = $3
      WHERE id = $1 RETURNING id, status, note, handled_at`,
    [id, adminId, note],
  );
}

/** Admin: could not confirm with the person (or they changed their mind). */
export async function rejectDeletionRequest(id, adminId, note) {
  const r = await one('SELECT status FROM account_deletion_requests WHERE id = $1', [id]);
  if (!r) throw notFound('request_not_found', 'Request not found');
  if (r.status !== 'pending') throw conflict('already_decided', `This request is already ${r.status}`);
  return one(
    `UPDATE account_deletion_requests SET status = 'rejected', handled_by = $2, handled_at = now(), note = $3
      WHERE id = $1 RETURNING id, status, note, handled_at`,
    [id, adminId, note],
  );
}
