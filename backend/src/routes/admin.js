import { Router } from 'express';
import { runPushPass } from '../lib/pushWorker.js';
import { pushProvider, recordedPushes } from '../lib/push.js';
import { z } from 'zod';
import { many, one, tx } from '../lib/db.js';
import { asyncHandler, badRequest, conflict, notFound } from '../lib/errors.js';
import { intQuery, parse, passwordSchema } from '../lib/validate.js';
import { deleteProfile } from '../lib/profiles.js';
import { hashPassword } from '../lib/auth.js';
import { CLIENT_SELECT, clientRow, loadClient, reassignCustomer, transitionCustomer } from '../lib/customers.js';

export const adminRouter = Router();

/** Turns a Postgres unique-violation into a clean 409. */
const rethrowUnique = (message) => (err) => {
  if (err?.code === '23505') throw conflict('duplicate', message);
  throw err;
};

// ---------------------------------------------------------------- agents

const agentListSchema = z.object({
  status: z.enum(['pending', 'active', 'suspended']).optional(),
  q: z.string().trim().max(80).optional(),
});

// GET /api/admin/agents?status=pending|active|suspended
adminRouter.get(
  '/agents',
  asyncHandler(async (req, res) => {
    const f = parse(agentListSchema, req.query);
    const where = [];
    const params = [];
    if (f.status) {
      params.push(f.status);
      where.push(`a.status = $${params.length}`);
    }
    if (f.q) {
      params.push(`%${f.q}%`);
      where.push(`(a.full_name ILIKE $${params.length} OR a.phone ILIKE $${params.length})`);
    }

    const rows = await many(
      `SELECT a.id, a.full_name, a.phone, a.agency_name, a.role, a.status, a.must_change_password, a.created_at,
              COALESCE(json_agg(json_build_object('id', c.id, 'name', c.name)
                       ORDER BY c.sort_order) FILTER (WHERE c.id IS NOT NULL), '[]') AS communities,
              (SELECT count(*)::int FROM profiles p WHERE p.uploaded_by = a.id) AS profile_count
         FROM agents a
         LEFT JOIN agent_communities ac ON ac.agent_id = a.id
         LEFT JOIN communities c ON c.id = ac.community_id
         ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        GROUP BY a.id
        ORDER BY CASE a.status WHEN 'pending' THEN 0 ELSE 1 END, a.created_at DESC`,
      params,
    );
    res.json({ agents: rows });
  }),
);

/** Changes an agent's status, refusing to lock out the last active admin. */
async function setAgentStatus(id, status, actingAdminId) {
  const agent = await one('SELECT id, role, status FROM agents WHERE id = $1', [id]);
  if (!agent) throw notFound('agent_not_found', 'Agent not found');
  if (agent.id === actingAdminId && status !== 'active') {
    throw badRequest('cannot_change_self', 'You cannot suspend your own account');
  }
  if (agent.role === 'admin' && status !== 'active') {
    const others = await one(
      `SELECT count(*)::int AS n FROM agents WHERE role = 'admin' AND status = 'active' AND id <> $1`,
      [id],
    );
    if (others.n === 0) throw badRequest('last_admin', 'At least one active admin must remain');
  }
  return one(
    `UPDATE agents SET status = $2 WHERE id = $1
     RETURNING id, full_name, phone, agency_name, role, status, created_at`,
    [id, status],
  );
}

adminRouter.post(
  '/agents/:id/activate',
  asyncHandler(async (req, res) => {
    res.json({ agent: await setAgentStatus(Number(req.params.id), 'active', req.agent.id) });
  }),
);

adminRouter.post(
  '/agents/:id/suspend',
  asyncHandler(async (req, res) => {
    res.json({ agent: await setAgentStatus(Number(req.params.id), 'suspended', req.agent.id) });
  }),
);

const roleSchema = z.object({ role: z.enum(['agent', 'admin']) });

// POST /api/admin/agents/:id/role {role}
adminRouter.post(
  '/agents/:id/role',
  asyncHandler(async (req, res) => {
    const { role } = parse(roleSchema, req.body ?? {});
    const id = Number(req.params.id);
    if (id === req.agent.id) throw badRequest('cannot_change_self', 'You cannot change your own role');
    const agent = await one('SELECT id FROM agents WHERE id = $1', [id]);
    if (!agent) throw notFound('agent_not_found', 'Agent not found');
    res.json({
      agent: await one(
        `UPDATE agents SET role = $2 WHERE id = $1
         RETURNING id, full_name, phone, agency_name, role, status, created_at`,
        [id, role],
      ),
    });
  }),
);

const agentCommunitiesSchema = z.object({
  community_ids: z.array(z.number().int().positive()).min(1, 'Select at least one community'),
});

// PUT /api/admin/agents/:id/communities — admins can set them directly.
adminRouter.put(
  '/agents/:id/communities',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const { community_ids } = parse(agentCommunitiesSchema, req.body ?? {});
    const agent = await one('SELECT id FROM agents WHERE id = $1', [id]);
    if (!agent) throw notFound('agent_not_found', 'Agent not found');

    const valid = await many('SELECT id FROM communities WHERE id = ANY($1::int[])', [community_ids]);
    if (valid.length !== community_ids.length) {
      throw badRequest('invalid_communities', 'One or more communities do not exist');
    }
    await tx(async (client) => {
      await client.query('DELETE FROM agent_communities WHERE agent_id = $1', [id]);
      await client.query(
        'INSERT INTO agent_communities (agent_id, community_id) SELECT $1, unnest($2::int[])',
        [id, community_ids],
      );
    });
    const communities = await many(
      `SELECT c.id, c.name FROM agent_communities ac JOIN communities c ON c.id = ac.community_id
        WHERE ac.agent_id = $1 ORDER BY c.sort_order, c.name`,
      [id],
    );
    res.json({ communities });
  }),
);

// ---------------------------------------------------------------- master tables

const SIMPLE_MASTERS = {
  communities: 'communities',
  subcastes: 'subcastes', // POST additionally needs community_id — handled below
  professions: 'professions',
  educations: 'educations',
  marital_statuses: 'marital_statuses',
  complexions: 'complexions',
  countries: 'countries',
  religions: 'religions',
  languages: 'languages',
  food_habits: 'food_habits',
  occupation_types: 'occupation_types',
  nakshatrams: 'nakshatrams',
};

const simpleMasterSchema = z.object({
  name: z.string().trim().min(1, 'Enter a name').max(120),
  active: z.boolean().optional(),
  sort_order: z.coerce.number().int().min(0).max(9999).optional(),
});

const zodiacSchema = z.object({
  english_name: z.string().trim().min(1).max(60),
  indian_name: z.string().trim().min(1).max(60),
  sort_order: z.coerce.number().int().min(0).max(9999).optional(),
});

/** nakshatrams has no `active` column; the rest of the simple masters do. */
const hasActive = (table) => table !== 'nakshatrams';

function resolveTable(name) {
  if (name === 'zodiac_signs') return 'zodiac_signs';
  const table = SIMPLE_MASTERS[name];
  if (!table) throw badRequest('unknown_master_table', `Unknown master table '${name}'`);
  return table;
}

// POST /api/admin/masters/:table
adminRouter.post(
  '/masters/:table',
  asyncHandler(async (req, res) => {
    const table = resolveTable(req.params.table);

    if (table === 'zodiac_signs') {
      const body = parse(zodiacSchema, req.body ?? {});
      const row = await one(
        `INSERT INTO zodiac_signs (english_name, indian_name, sort_order)
         VALUES ($1,$2,COALESCE($3, (SELECT COALESCE(max(sort_order),0)+1 FROM zodiac_signs)))
         RETURNING *`,
        [body.english_name, body.indian_name, body.sort_order ?? null],
      ).catch(rethrowUnique('A zodiac sign with that name already exists'));
      return res.status(201).json({ row });
    }

    if (table === 'subcastes') {
      const body = parse(
        simpleMasterSchema.extend({ community_id: z.coerce.number().int().positive('Select a community') }),
        req.body ?? {},
      );
      const community = await one('SELECT id FROM communities WHERE id = $1', [body.community_id]);
      if (!community) throw badRequest('invalid_reference', 'Unknown community');
      const row = await one(
        `INSERT INTO subcastes (community_id, name, active, sort_order)
         VALUES ($1, $2, COALESCE($3, TRUE),
                 COALESCE($4, (SELECT COALESCE(max(sort_order), 0) + 1 FROM subcastes WHERE community_id = $1)))
         RETURNING *`,
        [body.community_id, body.name, body.active ?? null, body.sort_order ?? null],
      ).catch(rethrowUnique(`'${body.name}' already exists in that community`));
      return res.status(201).json({ row });
    }

    const body = parse(simpleMasterSchema, req.body ?? {});
    const cols = hasActive(table) ? '(name, active, sort_order)' : '(name, sort_order)';
    const vals = hasActive(table)
      ? `($1, COALESCE($2, TRUE), COALESCE($3, (SELECT COALESCE(max(sort_order),0)+1 FROM ${table})))`
      : `($1, COALESCE($2, (SELECT COALESCE(max(sort_order),0)+1 FROM ${table})))`;
    const params = hasActive(table)
      ? [body.name, body.active ?? null, body.sort_order ?? null]
      : [body.name, body.sort_order ?? null];

    const row = await one(`INSERT INTO ${table} ${cols} VALUES ${vals} RETURNING *`, params).catch(
      rethrowUnique(`'${body.name}' already exists in ${req.params.table}`),
    );
    res.status(201).json({ row });
  }),
);

// PATCH /api/admin/masters/:table/:id
adminRouter.patch(
  '/masters/:table/:id',
  asyncHandler(async (req, res) => {
    const table = resolveTable(req.params.table);
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('row_not_found', 'Row not found');

    const schema = table === 'zodiac_signs' ? zodiacSchema.partial() : simpleMasterSchema.partial();
    const body = parse(schema, req.body ?? {});
    if (body.active !== undefined && !hasActive(table)) delete body.active;

    const keys = Object.keys(body);
    if (!keys.length) throw badRequest('nothing_to_update', 'No fields supplied');

    const row = await one(
      `UPDATE ${table} SET ${keys.map((k, i) => `${k} = $${i + 2}`).join(', ')} WHERE id = $1 RETURNING *`,
      [id, ...keys.map((k) => body[k])],
    ).catch(rethrowUnique('That name is already in use'));
    if (!row) throw notFound('row_not_found', 'Row not found');
    res.json({ row });
  }),
);

// ---------------------------------------------------------------- community change requests

// GET /api/admin/community-requests
adminRouter.get(
  '/community-requests',
  asyncHandler(async (req, res) => {
    const status = ['pending', 'approved', 'rejected'].includes(req.query.status) ? req.query.status : null;
    const rows = await many(
      `SELECT ccr.id, ccr.status, ccr.created_at, ccr.decided_at,
              a.id AS agent_id, a.full_name AS agent_name, a.phone AS agent_phone, a.agency_name,
              c.id AS community_id, c.name AS community_name
         FROM community_change_requests ccr
         JOIN agents a ON a.id = ccr.agent_id
         JOIN communities c ON c.id = ccr.community_id
        ${status ? 'WHERE ccr.status = $1' : ''}
        ORDER BY CASE WHEN ccr.status = 'pending' THEN 0 ELSE 1 END, ccr.created_at DESC`,
      status ? [status] : [],
    );
    res.json({ community_requests: rows });
  }),
);

async function decideCommunityRequest(id, decision, adminId) {
  const row = await one('SELECT * FROM community_change_requests WHERE id = $1', [id]);
  if (!row) throw notFound('request_not_found', 'Request not found');
  if (row.status !== 'pending') throw conflict('already_decided', `This request is already ${row.status}`);

  return tx(async (client) => {
    const { rows } = await client.query(
      `UPDATE community_change_requests SET status = $2, decided_by = $3, decided_at = now()
        WHERE id = $1 RETURNING *`,
      [id, decision, adminId],
    );
    if (decision === 'approved') {
      await client.query(
        `INSERT INTO agent_communities (agent_id, community_id) VALUES ($1,$2)
         ON CONFLICT DO NOTHING`,
        [row.agent_id, row.community_id],
      );
    }
    return rows[0];
  });
}

adminRouter.post(
  '/community-requests/:id/approve',
  asyncHandler(async (req, res) => {
    res.json({ community_request: await decideCommunityRequest(Number(req.params.id), 'approved', req.agent.id) });
  }),
);

adminRouter.post(
  '/community-requests/:id/reject',
  asyncHandler(async (req, res) => {
    res.json({ community_request: await decideCommunityRequest(Number(req.params.id), 'rejected', req.agent.id) });
  }),
);

// ---------------------------------------------------------------- password resets
//
// Forgot-password flow (SPEC §4 Auth). The agent asks from the login screen
// (POST /auth/forgot-password); the admin sees name + phone here, verifies the
// person out of band, and hands out a TEMPORARY password. That sets
// agents.must_change_password, so the agent can only reach /auth/me and
// /auth/change-password until they pick their own password.

const tempPasswordSchema = z.object({ temporary_password: passwordSchema });

/** Sets a temporary password and flags the account; returns the public agent row. */
async function issueTemporaryPassword(agentId, temporaryPassword, adminId) {
  const agent = await one('SELECT id FROM agents WHERE id = $1', [agentId]);
  if (!agent) throw notFound('agent_not_found', 'Agent not found');
  const hash = await hashPassword(temporaryPassword);
  return tx(async (client) => {
    const { rows } = await client.query(
      `UPDATE agents SET password_hash = $2, must_change_password = TRUE WHERE id = $1
       RETURNING id, full_name, phone, agency_name, role, status, must_change_password, created_at`,
      [agentId, hash],
    );
    // Any open request from this agent is now satisfied.
    await client.query(
      `UPDATE password_reset_requests SET status = 'approved', decided_by = $2, decided_at = now()
        WHERE agent_id = $1 AND status = 'pending'`,
      [agentId, adminId],
    );
    return rows[0];
  });
}

// GET /api/admin/password-resets?status=pending|approved|rejected
adminRouter.get(
  '/password-resets',
  asyncHandler(async (req, res) => {
    const status = ['pending', 'approved', 'rejected'].includes(req.query.status) ? req.query.status : null;
    const rows = await many(
      `SELECT prr.id, prr.status, prr.requested_at, prr.decided_at,
              a.id AS agent_id, a.full_name AS agent_name, a.phone AS agent_phone, a.agency_name,
              a.status AS agent_status, d.full_name AS decided_by_name
         FROM password_reset_requests prr
         JOIN agents a ON a.id = prr.agent_id
         LEFT JOIN agents d ON d.id = prr.decided_by
        ${status ? 'WHERE prr.status = $1' : ''}
        ORDER BY CASE WHEN prr.status = 'pending' THEN 0 ELSE 1 END, prr.requested_at DESC
        LIMIT 200`,
      status ? [status] : [],
    );
    res.json({ password_resets: rows });
  }),
);

async function loadPendingReset(id) {
  const row = await one('SELECT * FROM password_reset_requests WHERE id = $1', [id]);
  if (!row) throw notFound('request_not_found', 'Request not found');
  if (row.status !== 'pending') throw conflict('already_decided', `This request is already ${row.status}`);
  return row;
}

// POST /api/admin/password-resets/:id/approve {temporary_password}
adminRouter.post(
  '/password-resets/:id/approve',
  asyncHandler(async (req, res) => {
    const { temporary_password } = parse(tempPasswordSchema, req.body ?? {});
    const row = await loadPendingReset(Number(req.params.id));
    const agent = await issueTemporaryPassword(row.agent_id, temporary_password, req.agent.id);
    res.json({ password_reset: { ...row, status: 'approved', decided_by: req.agent.id }, agent });
  }),
);

// POST /api/admin/password-resets/:id/reject
adminRouter.post(
  '/password-resets/:id/reject',
  asyncHandler(async (req, res) => {
    const row = await loadPendingReset(Number(req.params.id));
    const updated = await one(
      `UPDATE password_reset_requests SET status = 'rejected', decided_by = $2, decided_at = now()
        WHERE id = $1 RETURNING *`,
      [row.id, req.agent.id],
    );
    res.json({ password_reset: updated });
  }),
);

// POST /api/admin/agents/:id/reset-password {temporary_password}
// Same effect without a request — for agents who phoned the admin instead.
adminRouter.post(
  '/agents/:id/reset-password',
  asyncHandler(async (req, res) => {
    const { temporary_password } = parse(tempPasswordSchema, req.body ?? {});
    const id = Number(req.params.id);
    if (id === req.agent.id) throw badRequest('cannot_change_self', 'Change your own password from Settings');
    res.json({ agent: await issueTemporaryPassword(id, temporary_password, req.agent.id) });
  }),
);

// ---------------------------------------------------------------- customers (SPEC §9.5)
//
// Gandharva accounts across every agent. Same rows as GET /clients (with the
// owning agent), same transitions as the agent's Clients tab — admins may
// also re-activate a rejected customer and move one to another agent.

const customerListSchema = z.object({
  status: z.enum(['guest', 'pending', 'active', 'rejected', 'suspended']).optional(),
  q: z.string().trim().max(80).optional(),
});

// GET /api/admin/customers?status=&q=
adminRouter.get(
  '/customers',
  asyncHandler(async (req, res) => {
    const f = parse(customerListSchema, req.query);
    const where = [];
    const params = [];
    if (f.status) {
      params.push(f.status);
      where.push(`cu.status = $${params.length}`);
    }
    if (f.q) {
      params.push(`%${f.q}%`);
      where.push(`(cu.full_name ILIKE $${params.length} OR cu.phone ILIKE $${params.length})`);
    }
    const rows = await many(
      `${CLIENT_SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
        ORDER BY CASE cu.status WHEN 'pending' THEN 0 ELSE 1 END, cu.created_at DESC, cu.id DESC`,
      params,
    );
    res.json({ customers: rows.map((r) => clientRow(r, { admin: true })) });
  }),
);

/** POST /api/admin/customers/:id/<action>; 409 wrong_status when not allowed from the current status. */
function customerAction(action, from) {
  return asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('customer_not_found', 'Customer not found');
    await transitionCustomer({ id, action, actorId: req.agent.id, from });
    res.json({ customer: clientRow(await loadClient(id), { admin: true }) });
  });
}

// pending / rejected / suspended → active (first approval also flips a hidden profile to active)
adminRouter.post('/customers/:id/activate', customerAction('activate', ['pending', 'rejected', 'suspended']));
adminRouter.post('/customers/:id/suspend', customerAction('suspend', ['active']));
adminRouter.post('/customers/:id/reject', customerAction('reject', ['pending']));

const reassignSchema = z.object({ agent_id: z.coerce.number().int().positive('Pick an agent') });

// PUT /api/admin/customers/:id/agent {agent_id} — reassign: the profile's
// uploaded_by moves too and pending change requests are cancelled (SPEC §9.5).
adminRouter.put(
  '/customers/:id/agent',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    const { agent_id } = parse(reassignSchema, req.body ?? {});
    const customer = await loadClient(id);
    if (!customer) throw notFound('customer_not_found', 'Customer not found');
    if (customer.agent_id === agent_id) throw badRequest('same_agent', 'The customer is already with that agent');

    const agent = await one('SELECT id, status FROM agents WHERE id = $1', [agent_id]);
    if (!agent) throw notFound('agent_not_found', 'Agent not found');
    if (agent.status !== 'active') throw badRequest('agent_not_active', 'That agent is not active');

    await tx(async (client) => {
      await reassignCustomer(client, { customerId: id, toAgentId: agent_id, actorId: req.agent.id });
    });
    res.json({ customer: clientRow(await loadClient(id), { admin: true }) });
  }),
);

// ---------------------------------------------------------------- logs

const logQuerySchema = z.object({
  limit: intQuery(1, 500).default(100),
  page: intQuery(1).default(1),
  agent_id: intQuery(1),
  profile_id: intQuery(1),
});

// GET /api/admin/logs/shares
adminRouter.get(
  '/logs/shares',
  asyncHandler(async (req, res) => {
    const f = parse(logQuerySchema, req.query);
    const where = [];
    const params = [];
    if (f.agent_id) {
      params.push(f.agent_id);
      where.push(`sl.agent_id = $${params.length}`);
    }
    if (f.profile_id) {
      params.push(f.profile_id);
      where.push(`sl.profile_id = $${params.length}`);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const total = await one(`SELECT count(*)::int AS n FROM share_logs sl ${whereSql}`, params);
    const rows = await many(
      `SELECT sl.id, sl.profile_id, sl.method, sl.shared_at,
              p.full_name AS profile_name,
              a.id AS agent_id, a.full_name AS agent_name, a.agency_name
         FROM share_logs sl
         JOIN profiles p ON p.id = sl.profile_id
         JOIN agents a ON a.id = sl.agent_id
         ${whereSql}
        ORDER BY sl.shared_at DESC
        LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, f.limit, (f.page - 1) * f.limit],
    );
    res.json({ total: total.n, page: f.page, limit: f.limit, logs: rows });
  }),
);

// GET /api/admin/logs/contacts
adminRouter.get(
  '/logs/contacts',
  asyncHandler(async (req, res) => {
    const f = parse(logQuerySchema, req.query);
    const where = [];
    const params = [];
    if (f.agent_id) {
      params.push(f.agent_id);
      where.push(`cr.requester_id = $${params.length}`);
    }
    if (f.profile_id) {
      params.push(f.profile_id);
      where.push(`cr.profile_id = $${params.length}`);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const total = await one(`SELECT count(*)::int AS n FROM contact_requests cr ${whereSql}`, params);
    const rows = await many(
      `SELECT cr.id, cr.profile_id, cr.status, cr.note, cr.requested_at, cr.decided_at, cr.expires_at,
              p.full_name AS profile_name,
              r.id AS requester_id, r.full_name AS requester_name, r.agency_name AS requester_agency,
              d.full_name AS decided_by_name,
              u.full_name AS uploader_name
         FROM contact_requests cr
         JOIN profiles p ON p.id = cr.profile_id
         JOIN agents r ON r.id = cr.requester_id
         JOIN agents u ON u.id = p.uploaded_by
         LEFT JOIN agents d ON d.id = cr.decided_by
         ${whereSql}
        ORDER BY cr.requested_at DESC
        LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, f.limit, (f.page - 1) * f.limit],
    );
    res.json({ total: total.n, page: f.page, limit: f.limit, logs: rows });
  }),
);

// GET /api/admin/stats — small dashboard summary.
adminRouter.get(
  '/stats',
  asyncHandler(async (_req, res) => {
    const stats = await one(`
      SELECT (SELECT count(*)::int FROM agents WHERE status = 'active')  AS active_agents,
             (SELECT count(*)::int FROM agents WHERE status = 'pending') AS pending_agents,
             (SELECT count(*)::int FROM profiles WHERE status = 'active') AS active_profiles,
             (SELECT count(*)::int FROM profiles) AS total_profiles,
             (SELECT count(*)::int FROM contact_requests WHERE status = 'pending') AS pending_contact_requests,
             (SELECT count(*)::int FROM community_change_requests WHERE status = 'pending') AS pending_community_requests,
             (SELECT count(*)::int FROM password_reset_requests WHERE status = 'pending') AS pending_password_resets,
             (SELECT count(*)::int FROM hold_requests WHERE status = 'pending') AS pending_hold_requests,
             (SELECT count(*)::int FROM profiles WHERE status = 'on_hold') AS on_hold_profiles,
             (SELECT count(*)::int FROM share_logs WHERE shared_at > now() - interval '7 days') AS shares_last_7_days,
             -- SPEC §9.5: the Gandharva side of the dashboard.
             (SELECT count(*)::int FROM customers WHERE status = 'pending') AS pending_customers,
             (SELECT count(*)::int FROM customers WHERE status = 'active') AS active_customers,
             (SELECT count(*)::int FROM customers WHERE status = 'guest') AS guest_customers,
             (SELECT count(*)::int FROM payments WHERE status = 'paid' AND provider <> 'waived') AS paid_registrations,
             (SELECT count(*)::int FROM customer_interests WHERE status = 'pending') AS pending_interests,
             (SELECT count(*)::int FROM agent_change_requests WHERE status = 'pending') AS pending_agent_changes`);
    res.json({ stats });
  }),
);

// DELETE /api/admin/profiles/:id — hard delete of any profile. Uploaders delete
// their own through DELETE /api/profiles/:id; both share lib/profiles.js deleteProfile.
adminRouter.delete(
  '/profiles/:id',
  asyncHandler(async (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) throw notFound('profile_not_found', 'Profile not found');
    const row = await one('SELECT id FROM profiles WHERE id = $1', [id]);
    if (!row) throw notFound('profile_not_found', 'Profile not found');
    await deleteProfile(id);
    res.json({ ok: true });
  }),
);

// ---------------------------------------------------------------- push (SPEC §9.16)

// POST /api/admin/push/run — one sender pass now → {devices, sent}.
adminRouter.post(
  '/push/run',
  asyncHandler(async (_req, res) => {
    res.json(await runPushPass());
  }),
);

// GET /api/admin/push/outbox — the log provider's recorded pushes (404 otherwise).
adminRouter.get(
  '/push/outbox',
  asyncHandler(async (_req, res) => {
    if (pushProvider() !== 'log') throw notFound('not_available', 'Only with PUSH_PROVIDER=log');
    res.json({ pushes: recordedPushes() });
  }),
);
