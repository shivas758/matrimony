// Customer (Gandharva account) helpers — SPEC §9.2 / §9.4 / §9.5 / §9.6 / §9.9.
// Shared by routes/customerAuth.js, routes/customerApp.js, routes/clients.js
// and routes/admin.js so a customer, an interest or an agent-change request
// has ONE wire shape wherever it appears.
import { many, one, tx } from './db.js';
import { config } from './config.js';
import { conflict, forbidden, notFound } from './errors.js';
import { agentDirectory, customerPublic } from './serialize.js';
import { LIVE_INTEREST, profileSummary } from './profiles.js';

export const CUSTOMER_COLUMNS = `id, full_name, phone, agent_id, status, source, phone_verified_at,
  approved_by, approved_at, last_login_at, created_at, updated_at`;

/** Customer routes serve photos from their own endpoint (SPEC §9.9). */
export const CUSTOMER_PHOTO_BASE = '/api/customer/photos';

/**
 * Where one of a customer's own profiles stands (SPEC §9.12): unpaid →
 * 'payment_pending'; paid but the customer is not approved yet →
 * 'awaiting_approval'; live to others → 'live'; anything else (hidden by the
 * agent, engaged, married, on hold) → 'hidden'.
 */
export function profileVisibility(profile, customerStatus) {
  if (!profile.paid_at) return 'payment_pending';
  if (customerStatus !== 'active') return 'awaiting_approval';
  return profile.status === 'active' ? 'live' : 'hidden';
}

/**
 * 'full' when the customer is active and at least one of their profiles is
 * paid, else 'guest' (SPEC §9.12). Needs `status` and `id`.
 */
export async function customerAccessLevel(customer) {
  if (customer.status !== 'active') return 'guest';
  const paid = await one('SELECT 1 FROM profiles WHERE customer_id = $1 AND paid_at IS NOT NULL LIMIT 1', [customer.id]);
  return paid ? 'full' : 'guest';
}

/** The customer's profiles, oldest first, with what the app needs for its list. */
export async function ownProfilesSummary(customer) {
  const rows = await many(
    `SELECT p.id, p.full_name, p.gender, date_part('year', age(p.dob))::int AS age, p.status, p.paid_at,
            c.id AS community_id, c.name AS community_name, sc.id AS subcaste_id, sc.name AS subcaste_name,
            (SELECT ph.id FROM profile_photos ph WHERE ph.profile_id = p.id
              ORDER BY ph.is_primary DESC, ph.sort_order, ph.id LIMIT 1) AS photo_id,
            (SELECT d.id FROM profile_delete_requests d
              WHERE d.profile_id = p.id AND d.status = 'pending' LIMIT 1) AS delete_request_id
       FROM profiles p
       JOIN communities c ON c.id = p.community_id
       LEFT JOIN subcastes sc ON sc.id = p.subcaste_id
      WHERE p.customer_id = $1
      ORDER BY p.created_at, p.id`,
    [customer.id],
  );
  return rows.map((r) => ({
    ...profileSummary(r, { photoId: r.photo_id, photoUrlBase: CUSTOMER_PHOTO_BASE }),
    paid: r.paid_at != null,
    paid_at: r.paid_at ?? null,
    visibility: profileVisibility(r, customer.status),
    delete_request_id: r.delete_request_id ?? null,
  }));
}

/** The customer row for a (normalised) mobile number, or null. */
export async function findCustomerByPhone(phone) {
  return one(`SELECT ${CUSTOMER_COLUMNS} FROM customers WHERE phone = $1`, [phone]);
}

/**
 * The full "me" object (SPEC §9.9): the customer, their agent as the directory
 * shape (+ communities), their profile id and any pending agent change.
 * Returns null when the customer no longer exists.
 */
export async function loadCustomerMe(customerId) {
  const customer = await one(`SELECT ${CUSTOMER_COLUMNS} FROM customers WHERE id = $1`, [customerId]);
  if (!customer) return null;

  const [agent, communities, profiles, change] = await Promise.all([
    customer.agent_id
      ? one('SELECT id, full_name, agency_name, phone, city, status FROM agents WHERE id = $1', [customer.agent_id])
      : null,
    customer.agent_id
      ? many(
          `SELECT c.id, c.name
             FROM agent_communities ac JOIN communities c ON c.id = ac.community_id
            WHERE ac.agent_id = $1
            ORDER BY c.sort_order, c.name`,
          [customer.agent_id],
        )
      : [],
    ownProfilesSummary(customer),
    one(
      `SELECT r.id, r.created_at, a.id AS to_agent_id, a.full_name, a.agency_name, a.city
         FROM agent_change_requests r JOIN agents a ON a.id = r.to_agent_id
        WHERE r.customer_id = $1 AND r.status = 'pending'
        ORDER BY r.created_at DESC, r.id DESC
        LIMIT 1`,
      [customer.id],
    ),
  ]);

  const paid = profiles.some((p) => p.paid);
  const approved = customer.status === 'active';
  const out = customerPublic(customer, {
    agent: agent ? agentDirectory(agent, communities) : null,
    // v1.0 app: its single profile is the oldest one.
    profileId: profiles[0]?.id ?? null,
    pendingAgentChange: change
      ? {
          id: change.id,
          to_agent: {
            id: change.to_agent_id,
            full_name: change.full_name,
            agency_name: change.agency_name,
            city: change.city ?? null,
          },
          created_at: change.created_at,
        }
      : null,
  });
  // SPEC §9.12: guest mode until linked + registered + paid + approved.
  out.access = approved && paid ? 'full' : 'guest';
  out.profiles = profiles;
  out.max_profiles = config.payments.maxCustomerProfiles;
  out.profile_fee_inr = config.payments.profileFeeInr;
  out.payment_provider = config.payments.provider;
  out.unlock = {
    agent_linked: customer.agent_id != null,
    profile_registered: profiles.length > 0,
    paid,
    approved,
  };
  return out;
}

// ---------------------------------------------------------------- embedded profile summaries

const PRIMARY_PHOTO = (alias) =>
  `(SELECT ph.id FROM profile_photos ph
     WHERE ph.profile_id = ${alias}.id ORDER BY ph.is_primary DESC, ph.sort_order, ph.id LIMIT 1)`;

/**
 * The columns profileSummary() needs for the profile aliased `alias`, each
 * prefixed `${prefix}_` so several summaries fit in one row. Pair with
 * summaryJoins(alias, …) and read back with summaryFrom(row, prefix).
 * Public fields only — never a protected column (SPEC §9.8).
 */
const summaryColumns = (alias, prefix) => `
         ${alias}.id AS ${prefix}_id, ${alias}.full_name AS ${prefix}_name, ${alias}.gender AS ${prefix}_gender,
         date_part('year', age(${alias}.dob))::int AS ${prefix}_age, ${alias}.status AS ${prefix}_status,
         ${alias}c.id AS ${prefix}_community_id, ${alias}c.name AS ${prefix}_community_name,
         ${alias}sc.id AS ${prefix}_subcaste_id, ${alias}sc.name AS ${prefix}_subcaste_name,
         ${PRIMARY_PHOTO(alias)} AS ${prefix}_photo_id`;

const summaryJoins = (alias, on) => `
    LEFT JOIN profiles ${alias} ON ${on}
    LEFT JOIN communities ${alias}c ON ${alias}c.id = ${alias}.community_id
    LEFT JOIN subcastes ${alias}sc ON ${alias}sc.id = ${alias}.subcaste_id`;

/** profileSummary() from prefixed columns; null when the profile is absent. */
export function summaryFrom(row, prefix, photoUrlBase = '/api/photos') {
  if (row[`${prefix}_id`] == null) return null;
  return profileSummary(
    {
      id: row[`${prefix}_id`],
      full_name: row[`${prefix}_name`],
      gender: row[`${prefix}_gender`],
      age: row[`${prefix}_age`],
      community_id: row[`${prefix}_community_id`],
      community_name: row[`${prefix}_community_name`],
      subcaste_id: row[`${prefix}_subcaste_id`],
      subcaste_name: row[`${prefix}_subcaste_name`],
      status: row[`${prefix}_status`],
    },
    { photoId: row[`${prefix}_photo_id`], photoUrlBase },
  );
}

/** Contact card of an agent for the other party's agent (SPEC §9.4). */
const agentCard = (row, prefix) => ({
  id: row[`${prefix}_id`],
  full_name: row[`${prefix}_name`],
  agency_name: row[`${prefix}_agency`],
  phone: row[`${prefix}_phone`],
});

// ---------------------------------------------------------------- clients (SPEC §9.5)

/** Join condition: `p` is the customer's oldest profile (the v1.0 "one profile"). */
const OLDEST_PROFILE = (cu) =>
  `p.id = (SELECT x.id FROM profiles x WHERE x.customer_id = ${cu}.id ORDER BY x.created_at, x.id LIMIT 1)`;

/** Every profile of the customer as JSON (SPEC §9.12), oldest first. Public fields + paid_at. */
const PROFILES_JSON = (cu) => `COALESCE((
    SELECT json_agg(json_build_object(
             'id', x.id, 'full_name', x.full_name, 'gender', x.gender,
             'age', date_part('year', age(x.dob))::int, 'status', x.status, 'paid_at', x.paid_at,
             'community_id', xc.id, 'community_name', xc.name,
             'subcaste_id', xs.id, 'subcaste_name', xs.name,
             'photo_id', (SELECT ph.id FROM profile_photos ph WHERE ph.profile_id = x.id
                           ORDER BY ph.is_primary DESC, ph.sort_order, ph.id LIMIT 1),
             'delete_request_id', (SELECT d.id FROM profile_delete_requests d
                                    WHERE d.profile_id = x.id AND d.status = 'pending' LIMIT 1))
           ORDER BY x.created_at, x.id)
      FROM profiles x
      JOIN communities xc ON xc.id = x.community_id
      LEFT JOIN subcastes xs ON xs.id = x.subcaste_id
     WHERE x.customer_id = ${cu}.id), '[]'::json)`;

/**
 * A customer with their agent, their profile (summary), live interests count
 * and the latest pending agent change. Alias `cu`; filter on cu.* / a.*.
 */
export const CLIENT_SELECT = `
  SELECT cu.id, cu.full_name, cu.phone, cu.agent_id, cu.status, cu.source, cu.phone_verified_at,
         cu.approved_by, cu.approved_at, cu.last_login_at, cu.created_at, cu.updated_at,
         a.full_name AS agent_name, a.agency_name AS agent_agency,
         ${summaryColumns('p', 'profile')},
         ${PROFILES_JSON('cu')} AS profiles_json,
         -- Interests still in play (pending, or accepted and unexpired — same
         -- predicate as visibilityClause); withdrawn/declined/lapsed ones are history.
         (SELECT count(*)::int FROM customer_interests ci
           WHERE ci.customer_id = cu.id AND ${LIVE_INTEREST}) AS interests_count,
         r.id AS change_id, r.note AS change_note, r.created_at AS change_created_at,
         ta.id AS change_to_agent_id, ta.full_name AS change_to_agent_name,
         ta.agency_name AS change_to_agent_agency, ta.city AS change_to_agent_city
    FROM customers cu
    LEFT JOIN agents a ON a.id = cu.agent_id
    ${summaryJoins('p', OLDEST_PROFILE('cu'))}
    LEFT JOIN LATERAL (
      SELECT id, to_agent_id, note, created_at FROM agent_change_requests
       WHERE customer_id = cu.id AND status = 'pending'
       ORDER BY created_at DESC, id DESC LIMIT 1) r ON TRUE
    LEFT JOIN agents ta ON ta.id = r.to_agent_id`;

/**
 * Client row (SPEC §9.5). `admin` adds the owning agent — an agent only ever
 * lists their own clients, so they do not need it.
 */
export function clientRow(row, { admin = false } = {}) {
  return {
    ...customerPublic(row, {
      ...(admin
        ? { agent: row.agent_id ? { id: row.agent_id, full_name: row.agent_name, agency_name: row.agent_agency } : null }
        : {}),
      profileId: row.profile_id ?? null,
      pendingAgentChange: row.change_id
        ? {
            id: row.change_id,
            to_agent: {
              id: row.change_to_agent_id,
              full_name: row.change_to_agent_name,
              agency_name: row.change_to_agent_agency,
              city: row.change_to_agent_city ?? null,
            },
            note: row.change_note,
            created_at: row.change_created_at,
          }
        : null,
    }),
    agent_id: row.agent_id,
    last_login_at: row.last_login_at ?? null,
    profile: summaryFrom(row, 'profile'),
    profiles: (Array.isArray(row.profiles_json) ? row.profiles_json : []).map((x) => ({
      ...profileSummary(x, { photoId: x.photo_id }),
      paid: x.paid_at != null,
      paid_at: x.paid_at ?? null,
      visibility: profileVisibility(x, row.status),
      delete_request_id: x.delete_request_id ?? null,
    })),
    interests_count: row.interests_count,
  };
}

/** One client row by id, or null. */
export async function loadClient(id) {
  if (!Number.isInteger(id) || id <= 0) return null;
  return one(`${CLIENT_SELECT} WHERE cu.id = $1`, [id]);
}

/** A client the agent may act on: their own, or any for an admin. */
export async function loadClientFor(id, agent) {
  const row = await loadClient(id);
  if (!row) throw notFound('customer_not_found', 'Customer not found');
  if (!agent.is_admin && row.agent_id !== agent.id) {
    throw forbidden('not_your_client', 'This customer is attached to another agent');
  }
  return row;
}

/**
 * Status changes (SPEC §9.2 lifecycle / §9.5). The first move to `active`
 * (pending or rejected → active) records who approved and flips a profile
 * the customer filled in while waiting from `hidden` to `active`.
 * `from` lets admins widen the allowed source statuses. 409 wrong_status.
 */
const CUSTOMER_ACTIONS = {
  approve: { from: ['pending'], to: 'active' },
  reject: { from: ['pending'], to: 'rejected' },
  suspend: { from: ['active'], to: 'suspended' },
  activate: { from: ['suspended'], to: 'active' },
};

export async function transitionCustomer({ id, action, actorId, from }) {
  const spec = CUSTOMER_ACTIONS[action];
  if (!spec) throw new Error(`unknown customer action ${action}`);
  const allowed = from ?? spec.from;

  return tx(async (client) => {
    const { rows } = await client.query('SELECT id, status, approved_at FROM customers WHERE id = $1 FOR UPDATE', [id]);
    const cu = rows[0];
    if (!cu) throw notFound('customer_not_found', 'Customer not found');
    if (!allowed.includes(cu.status)) {
      throw conflict('wrong_status', `This customer is ${cu.status} — ${action} needs ${allowed.join(' or ')}`);
    }
    const firstApproval = spec.to === 'active' && cu.approved_at === null;
    if (firstApproval) {
      await client.query(
        `UPDATE customers SET status = $2, approved_by = $3, approved_at = now(), updated_at = now() WHERE id = $1`,
        [id, spec.to, actorId],
      );
      // Profiles they filled in (and paid for) while waiting go live with
      // them (SPEC §9.2 / §9.12); unpaid ones stay hidden until paid.
      await client.query(
        `UPDATE profiles SET status = 'active', updated_at = now()
          WHERE customer_id = $1 AND status = 'hidden' AND paid_at IS NOT NULL`,
        [id],
      );
    } else {
      await client.query('UPDATE customers SET status = $2, updated_at = now() WHERE id = $1', [id, spec.to]);
    }
    return { id, from: cu.status, to: spec.to };
  });
}

/**
 * Moves a customer to another agent (SPEC §9.6 approve, admin reassign):
 * customers.agent_id, the profile's uploaded_by, and every other pending
 * change request of theirs is cancelled. Runs on the caller's tx client.
 */
export async function reassignCustomer(client, { customerId, toAgentId, actorId, keepRequestId = null }) {
  // A guest given an agent by an admin now waits for that agent (SPEC §9.12).
  await client.query(
    `UPDATE customers SET agent_id = $2, status = CASE WHEN status = 'guest' THEN 'pending' ELSE status END,
            updated_at = now() WHERE id = $1`,
    [customerId, toAgentId],
  );
  await client.query('UPDATE profiles SET uploaded_by = $2, updated_at = now() WHERE customer_id = $1', [
    customerId,
    toAgentId,
  ]);
  await client.query(
    `UPDATE agent_change_requests SET status = 'cancelled', decided_by = $2, decided_at = now()
      WHERE customer_id = $1 AND status = 'pending' AND ($3::int IS NULL OR id <> $3)`,
    [customerId, actorId, keepRequestId],
  );
}

// ---------------------------------------------------------------- interests (SPEC §9.4)

/**
 * An interest with the customer, the customer's agent, the target profile
 * and its uploader, and the customer's own profile. Alias `ci`; the target
 * profile is `p`, the customer `cu`.
 */
export const INTEREST_SELECT = `
  SELECT ci.id, ci.customer_id, ci.profile_id, ci.from_profile_id, ci.status, ci.note, ci.created_at,
         ci.decided_by, ci.decided_at, ci.access_expires_at,
         -- Computed in SQL so the countdown uses one clock (like contact_requests).
         CASE WHEN ci.status = 'accepted' AND ci.access_expires_at > now()
              THEN CEIL(EXTRACT(EPOCH FROM (ci.access_expires_at - now())) / 86400)::int
         END AS days_left,
         (ci.status = 'accepted' AND ci.access_expires_at <= now()) AS is_expired,
         cu.full_name AS customer_name, cu.phone AS customer_phone, cu.agent_id AS customer_agent_id,
         ca.full_name AS customer_agent_name, ca.agency_name AS customer_agent_agency,
         ca.phone AS customer_agent_phone, ca.role AS customer_agent_role,
         p.uploaded_by AS target_agent_id, ua.full_name AS target_agent_name,
         ua.agency_name AS target_agent_agency, ua.phone AS target_agent_phone,
         ${summaryColumns('p', 'profile')},
         ${summaryColumns('cp', 'cprofile')}
    FROM customer_interests ci
    JOIN customers cu ON cu.id = ci.customer_id
    JOIN agents ca ON ca.id = cu.agent_id
    JOIN profiles p ON p.id = ci.profile_id
    JOIN agents ua ON ua.id = p.uploaded_by
    LEFT JOIN communities pc ON pc.id = p.community_id
    LEFT JOIN subcastes psc ON psc.id = p.subcaste_id
    ${summaryJoins('cp', 'cp.id = ci.from_profile_id')}`;

/**
 * Interest row. For a customer viewer: {id, status, note, created_at,
 * decided_at, days_left, access_expires_at, profile} — never anything about
 * agents (SPEC §9.9). For an agent viewer (SPEC §9.4): the customer (phone
 * only for their own agent / admin), both profile summaries, and the other
 * party's agent — `customer_agent` for the target's uploader, `target_agent`
 * for the customer's agent. Admins get both.
 */
export function interestRow(row, { agent, customer } = {}) {
  const expired = Boolean(row.is_expired);
  const live = row.status === 'accepted' && !expired;
  const base = {
    id: row.id,
    // An accepted interest whose window lapsed reads as 'expired' (like customerAccess()).
    status: expired ? 'expired' : row.status,
    note: row.note,
    created_at: row.created_at,
    decided_at: row.decided_at,
    days_left: row.days_left ?? null,
  };

  if (customer) {
    return {
      ...base,
      access_expires_at: live ? row.access_expires_at : null,
      profile: summaryFrom(row, 'profile', CUSTOMER_PHOTO_BASE),
      // Which of my profiles is interested (SPEC §9.12).
      from_profile: summaryFrom(row, 'cprofile', CUSTOMER_PHOTO_BASE),
    };
  }

  const isCustomerAgent = agent.is_admin || row.customer_agent_id === agent.id;
  const isUploader = agent.is_admin || row.target_agent_id === agent.id;
  return {
    ...base,
    access_expires_at: row.access_expires_at,
    customer: {
      id: row.customer_id,
      full_name: row.customer_name,
      ...(isCustomerAgent ? { phone: row.customer_phone } : {}),
      agent_id: row.customer_agent_id,
    },
    customer_profile: summaryFrom(row, 'cprofile'),
    profile: summaryFrom(row, 'profile'),
    // The one place uploader identity crosses agents: only between the two
    // agents whose clients are involved (SPEC §9.4).
    ...(isUploader ? { customer_agent: agentCard(row, 'customer_agent') } : {}),
    ...(isCustomerAgent ? { target_agent: agentCard(row, 'target_agent') } : {}),
    can_decide: isUploader,
  };
}

/** One interest row (INTEREST_SELECT shape) by id, or null. */
export async function loadInterest(id) {
  if (!Number.isInteger(id) || id <= 0) return null;
  return one(`${INTEREST_SELECT} WHERE ci.id = $1`, [id]);
}

// ---------------------------------------------------------------- agent change (SPEC §9.6)

export const AGENT_CHANGE_SELECT = `
  SELECT r.id, r.customer_id, r.from_agent_id, r.to_agent_id, r.status, r.note, r.created_at,
         r.decided_by, r.decided_at,
         cu.full_name AS customer_name, cu.phone AS customer_phone, cu.agent_id AS customer_agent_id,
         cu.status AS customer_status,
         fa.full_name AS from_agent_name, fa.agency_name AS from_agent_agency,
         fa.city AS from_agent_city, fa.phone AS from_agent_phone,
         ta.full_name AS to_agent_name, ta.agency_name AS to_agent_agency,
         ta.city AS to_agent_city, ta.phone AS to_agent_phone,
         ${summaryColumns('p', 'profile')}
    FROM agent_change_requests r
    JOIN customers cu ON cu.id = r.customer_id
    JOIN agents fa ON fa.id = r.from_agent_id
    JOIN agents ta ON ta.id = r.to_agent_id
    ${summaryJoins('p', OLDEST_PROFILE('cu'))}`;

/**
 * Agent-change row. Customers see the request and both agents' directory
 * cards. Agents also get the customer (phone only while they are the
 * customer's CURRENT agent, or admin), the customer's profile summary,
 * which `box` it falls in for them and whether they may decide it.
 */
export function agentChangeRow(row, { agent, customer } = {}) {
  const base = {
    id: row.id,
    status: row.status,
    note: row.note,
    created_at: row.created_at,
    decided_at: row.decided_at,
    from_agent: agentDirectory({
      id: row.from_agent_id,
      full_name: row.from_agent_name,
      agency_name: row.from_agent_agency,
      city: row.from_agent_city,
      phone: row.from_agent_phone,
    }),
    to_agent: agentDirectory({
      id: row.to_agent_id,
      full_name: row.to_agent_name,
      agency_name: row.to_agent_agency,
      city: row.to_agent_city,
      phone: row.to_agent_phone,
    }),
  };
  if (customer) return base;

  const isCurrentAgent = agent.is_admin || row.customer_agent_id === agent.id;
  return {
    ...base,
    box: row.from_agent_id === agent.id ? 'outgoing' : row.to_agent_id === agent.id ? 'incoming' : null,
    customer: {
      id: row.customer_id,
      full_name: row.customer_name,
      ...(isCurrentAgent ? { phone: row.customer_phone } : {}),
      status: row.customer_status,
      agent_id: row.customer_agent_id,
    },
    customer_profile: summaryFrom(row, 'profile'),
    can_decide: row.status === 'pending' && (agent.is_admin || row.from_agent_id === agent.id),
  };
}

/** One agent-change row (AGENT_CHANGE_SELECT shape) by id, or null. */
export async function loadAgentChange(id) {
  if (!Number.isInteger(id) || id <= 0) return null;
  return one(`${AGENT_CHANGE_SELECT} WHERE r.id = $1`, [id]);
}

// ---------------------------------------------------------------- delete requests (SPEC §9.13)

export const DELETE_REQUEST_SELECT = `
  SELECT d.id, d.customer_id, d.profile_id, d.profile_name AS deleted_profile_name, d.status, d.reason, d.created_at,
         d.decided_by, d.decided_at,
         cu.full_name AS customer_name, cu.phone AS customer_phone, cu.agent_id AS customer_agent_id,
         ${summaryColumns('p', 'profile')}
    FROM profile_delete_requests d
    JOIN customers cu ON cu.id = d.customer_id
    ${summaryJoins('p', 'p.id = d.profile_id')}`;

/** Delete-request row; agents also get the customer (SPEC §9.13). */
export function deleteRequestRow(row, { agent, customer } = {}) {
  const base = {
    id: row.id,
    status: row.status,
    reason: row.reason,
    created_at: row.created_at,
    decided_at: row.decided_at,
    // Not row.profile_name: summaryColumns() uses that alias for the live profile.
    profile_name: row.deleted_profile_name,
    profile_id: row.profile_id,
  };
  if (customer) return base;
  return {
    ...base,
    profile: summaryFrom(row, 'profile'),
    customer: { id: row.customer_id, full_name: row.customer_name, phone: row.customer_phone, agent_id: row.customer_agent_id },
    can_decide: row.status === 'pending' && (agent.is_admin || row.customer_agent_id === agent.id),
  };
}

export async function loadDeleteRequest(id) {
  if (!Number.isInteger(id) || id <= 0) return null;
  return one(`${DELETE_REQUEST_SELECT} WHERE d.id = $1`, [id]);
}
