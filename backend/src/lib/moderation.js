// Report, block — SPEC §9.22 (Google Play user-generated-content policy).
//
// Reports: a customer or an agent reports a profile they can see; admins review
// and dismiss, hide the profile, or suspend the account behind it.
// Blocks: a customer's block works both ways (neither sees the other's
// profile); an agent's block hides the profile from that agent. The SQL
// predicates below are added to every visibility clause.
import { many, one, query, tx } from './db.js';
import { badRequest, conflict, notFound } from './errors.js';

export const REPORT_REASONS = [
  'fake_profile', 'inappropriate_photo', 'offensive_content', 'scam_or_fraud', 'harassment', 'other',
];

// ---- visibility predicates (used by lib/profiles.js and routes/customerApp.js) ----

/** Agent `$n`: not a profile they blocked. */
export const agentBlockSql = (n) =>
  `NOT EXISTS (SELECT 1 FROM blocks bl WHERE bl.blocker_agent_id = $${n} AND bl.profile_id = p.id)`;

/**
 * Customer `$n`: not a profile they blocked, and not a profile whose own customer
 * blocked one of theirs (blocks between families work both ways).
 */
export const customerBlockSql = (n) =>
  `NOT EXISTS (SELECT 1 FROM blocks bl WHERE bl.blocker_customer_id = $${n} AND bl.profile_id = p.id)
   AND NOT (p.customer_id IS NOT NULL AND EXISTS (
     SELECT 1 FROM blocks bl JOIN profiles mine ON mine.id = bl.profile_id
      WHERE bl.blocker_customer_id = p.customer_id AND mine.customer_id = $${n}))`;

// ---- reports -----------------------------------------------------------------------

/**
 * Files (or refreshes) a report on a profile the reporter can see — the caller
 * passes the visible row. One open report per reporter and profile.
 */
export async function createReport({ agentId = null, customerId = null, profile, reason, details }) {
  const who = agentId ? 'reporter_agent_id' : 'reporter_customer_id';
  const id = agentId ?? customerId;
  const open = await one(`SELECT id FROM reports WHERE ${who} = $1 AND profile_id = $2 AND status = 'open'`, [id, profile.id]);
  if (open) {
    return one(`UPDATE reports SET reason = $2, details = $3, created_at = now() WHERE id = $1 RETURNING id, status`, [
      open.id, reason, details ?? null,
    ]);
  }
  return one(
    `INSERT INTO reports (${who}, profile_id, profile_label, reason, details)
     VALUES ($1, $2, $3, $4, $5) RETURNING id, status`,
    [id, profile.id, profile.label, reason, details ?? null],
  );
}

/** Admin list (SPEC §9.22 A). */
export async function listReports(status) {
  const rows = await many(
    `SELECT r.*,
            ra.full_name AS ra_name, ra.phone AS ra_phone, rc.full_name AS rc_name, rc.phone AS rc_phone,
            p.full_name AS p_name, p.profile_code, p.status AS p_status,
            cu.id AS cu_id, cu.full_name AS cu_name, cu.phone AS cu_phone, cu.status AS cu_status,
            up.id AS up_id, up.full_name AS up_name, up.agent_code AS up_code, up.status AS up_status,
            (SELECT count(*)::int FROM reports x WHERE x.profile_id = r.profile_id) AS on_profile
       FROM reports r
       LEFT JOIN agents ra ON ra.id = r.reporter_agent_id
       LEFT JOIN customers rc ON rc.id = r.reporter_customer_id
       LEFT JOIN profiles p ON p.id = r.profile_id
       LEFT JOIN customers cu ON cu.id = p.customer_id
       LEFT JOIN agents up ON up.id = p.uploaded_by
      ${status === 'all' ? '' : 'WHERE r.status = $1'}
      ORDER BY CASE WHEN r.status = 'open' THEN 0 ELSE 1 END, r.created_at DESC
      LIMIT 200`,
    status === 'all' ? [] : [status],
  );
  return rows.map((r) => ({
    id: r.id,
    reason: r.reason,
    details: r.details,
    status: r.status,
    action: r.action,
    note: r.note,
    created_at: r.created_at,
    handled_at: r.handled_at,
    reports_on_profile: r.on_profile,
    reporter: r.reporter_agent_id
      ? { type: 'agent', id: r.reporter_agent_id, full_name: r.ra_name, phone: r.ra_phone }
      : { type: 'customer', id: r.reporter_customer_id, full_name: r.rc_name, phone: r.rc_phone },
    profile: r.profile_id ? { id: r.profile_id, full_name: r.p_name ?? r.profile_label, profile_code: r.profile_code, status: r.p_status } : null,
    customer: r.cu_id ? { id: r.cu_id, full_name: r.cu_name, phone: r.cu_phone, status: r.cu_status } : null,
    agent: r.up_id ? { id: r.up_id, full_name: r.up_name, agent_code: r.up_code, status: r.up_status } : null,
  }));
}

async function openReport(client, id) {
  const { rows } = await client.query('SELECT * FROM reports WHERE id = $1 FOR UPDATE', [id]);
  const r = rows[0];
  if (!r) throw notFound('report_not_found', 'Report not found');
  if (r.status !== 'open') throw conflict('already_decided', `This report is already ${r.status}`);
  return r;
}

/** Marks every open report on the profile as actioned with `action`. */
async function closeReportsOnProfile(client, profileId, action, adminId, note) {
  await client.query(
    `UPDATE reports SET status = 'actioned', action = $2, handled_by = $3, handled_at = now(), note = COALESCE($4, note)
      WHERE profile_id = $1 AND status = 'open'`,
    [profileId, action, adminId, note],
  );
}

export async function dismissReport(id, adminId, note) {
  return tx(async (client) => {
    await openReport(client, id);
    const { rows } = await client.query(
      `UPDATE reports SET status = 'dismissed', handled_by = $2, handled_at = now(), note = $3
        WHERE id = $1 RETURNING id, status, action, note, handled_at`,
      [id, adminId, note],
    );
    return rows[0];
  });
}

export async function hideReportedProfile(id, adminId, note) {
  return tx(async (client) => {
    const r = await openReport(client, id);
    if (!r.profile_id) throw conflict('profile_gone', 'This profile no longer exists — dismiss the report');
    await client.query(`UPDATE profiles SET status = 'hidden', updated_at = now() WHERE id = $1`, [r.profile_id]);
    await closeReportsOnProfile(client, r.profile_id, 'profile_hidden', adminId, note);
    return (await client.query('SELECT id, status, action, note, handled_at FROM reports WHERE id = $1', [id])).rows[0];
  });
}

/** Suspends the profile's customer — or, for an agent-only profile, its uploader (never an admin). */
export async function suspendReportedAccount(id, adminId, note) {
  return tx(async (client) => {
    const r = await openReport(client, id);
    if (!r.profile_id) throw conflict('profile_gone', 'This profile no longer exists — dismiss the report');
    const p = (await client.query('SELECT id, customer_id, uploaded_by FROM profiles WHERE id = $1', [r.profile_id])).rows[0];
    if (p.customer_id) {
      await client.query(`UPDATE customers SET status = 'suspended', updated_at = now() WHERE id = $1`, [p.customer_id]);
    } else {
      const up = (await client.query('SELECT id, role FROM agents WHERE id = $1', [p.uploaded_by])).rows[0];
      if (up.role === 'admin') throw badRequest('cannot_suspend_admin', 'This profile was uploaded by an admin — hide it instead');
      await client.query(`UPDATE agents SET status = 'suspended' WHERE id = $1`, [up.id]);
    }
    await client.query(`UPDATE profiles SET status = 'hidden', updated_at = now() WHERE id = $1`, [p.id]);
    await closeReportsOnProfile(client, p.id, 'account_suspended', adminId, note);
    return (await client.query('SELECT id, status, action, note, handled_at FROM reports WHERE id = $1', [id])).rows[0];
  });
}

// ---- blocks -------------------------------------------------------------------------

/**
 * Blocks a visible profile (the caller passes the visible row). Customers also
 * withdraw pending interests between the two families.
 */
export async function blockProfile({ agentId = null, customerId = null, profile }) {
  return tx(async (client) => {
    const who = agentId ? 'blocker_agent_id' : 'blocker_customer_id';
    const id = agentId ?? customerId;
    await client.query(
      `INSERT INTO blocks (${who}, profile_id, profile_label) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
      [id, profile.id, profile.label],
    );
    if (customerId) {
      await client.query(
        `UPDATE customer_interests SET status = 'withdrawn', decided_at = now()
          WHERE status = 'pending'
            AND ((customer_id = $1 AND profile_id = $2)
              OR ($3::int IS NOT NULL AND customer_id = $3
                  AND profile_id IN (SELECT id FROM profiles WHERE customer_id = $1)))`,
        [customerId, profile.id, profile.customer_id ?? null],
      );
    }
    return { profile_id: profile.id, blocked: true };
  });
}

export async function unblockProfile({ agentId = null, customerId = null, profileId }) {
  const who = agentId ? 'blocker_agent_id' : 'blocker_customer_id';
  const res = await query(`DELETE FROM blocks WHERE ${who} = $1 AND profile_id = $2`, [agentId ?? customerId, profileId]);
  if (!res.rowCount) throw notFound('block_not_found', 'This profile is not blocked');
  return { profile_id: profileId, blocked: false };
}

export async function listBlocks({ agentId = null, customerId = null }) {
  const who = agentId ? 'blocker_agent_id' : 'blocker_customer_id';
  return many(
    `SELECT profile_id, profile_label, created_at FROM blocks WHERE ${who} = $1 ORDER BY created_at DESC`,
    [agentId ?? customerId],
  );
}
