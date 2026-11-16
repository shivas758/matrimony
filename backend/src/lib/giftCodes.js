// Gift codes (SPEC §9.23 B). Every agent gets GIFT_CODES_PER_AGENT free codes
// once; an admin can add more. A customer who enters one when publishing is
// linked to that agent, approved, and their profile goes live without the fee.
import { randomInt } from 'node:crypto';
import { config } from './config.js';
import { many, one, query } from './db.js';
import { badRequest, conflict, notFound } from './errors.js';
import { issueMissingProfileCodes } from './codes.js';

/** No 0/O/1/I — read aloud over the phone without mix-ups. */
export const GIFT_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const CODE_LENGTH = 6;

export function newGiftCode() {
  let s = '';
  for (let i = 0; i < CODE_LENGTH; i++) s += GIFT_ALPHABET[randomInt(GIFT_ALPHABET.length)];
  return `WB-${s}`;
}

/**
 * What the person typed → the stored form `WB-XXXXXX`, or null when it cannot
 * be a code. Case-insensitive; spaces, dashes and the WB prefix are optional.
 */
export function normaliseGiftCode(input) {
  if (typeof input !== 'string') return null;
  let s = input.toUpperCase().replace(/[\s\-_.]/g, '');
  if (s.length === CODE_LENGTH + 2 && s.startsWith('WB')) s = s.slice(2);
  if (s.length !== CODE_LENGTH) return null;
  for (const ch of s) if (!GIFT_ALPHABET.includes(ch)) return null;
  return `WB-${s}`;
}

/** Inserts `count` fresh codes for `agentId` on `client` (a tx client or the pool). */
export async function addGiftCodes(client, agentId, count, grantedBy = null) {
  const run = client ? (t, p) => client.query(t, p) : query;
  let added = 0;
  let attempts = 0;
  while (added < count && attempts < count * 5) {
    attempts++;
    // ON CONFLICT: a (vanishingly rare) duplicate code is simply drawn again.
    const { rowCount } = await run(
      `INSERT INTO gift_codes (code, agent_id, granted_by) VALUES ($1, $2, $3) ON CONFLICT (code) DO NOTHING`,
      [newGiftCode(), agentId, grantedBy],
    );
    added += rowCount;
  }
  return added;
}

/**
 * The free codes, once per agent (agents.gift_codes_granted_at). Called at
 * signup and lazily for agents created before v2.13. Returns how many were
 * issued now (0 when they already had them).
 */
export async function ensureInitialGiftCodes(agentId, client = null) {
  const per = config.agents.giftCodesPerAgent;
  const run = client ? (t, p) => client.query(t, p) : query;
  const { rows } = await run(
    `UPDATE agents SET gift_codes_granted_at = now()
      WHERE id = $1 AND gift_codes_granted_at IS NULL RETURNING id`,
    [agentId],
  );
  if (!rows.length || per <= 0) return 0;
  return addGiftCodes(client, agentId, per, null);
}

export async function giftCodeCounts(agentId) {
  const row = await one(
    `SELECT count(*) FILTER (WHERE status = 'unused')::int AS unused,
            count(*) FILTER (WHERE status = 'used')::int AS used,
            count(*)::int AS total
       FROM gift_codes WHERE agent_id = $1`,
    [agentId],
  );
  return { unused: row.unused, used: row.used, total: row.total };
}

/** The WhatsApp text an agent sends with one code. */
export function giftShareText(code, agent) {
  const who = agent.agent_code ? `${agent.full_name} (${agent.agent_code})` : agent.full_name;
  return (
    `Your free Wedbook Matrimony gift code: ${code}. Install Wedbook Matrimony, fill in your profile and ` +
    `enter this code when you publish it — no ₹${config.payments.profileFeeInr} fee. Your agent: ${who}`
  );
}

/** GET /my/gift-codes: unused first (oldest first), then used (newest first). */
export async function listGiftCodes(agent) {
  const rows = await many(
    `SELECT g.id, g.code, g.status, g.created_at, g.used_at, g.customer_id, g.profile_id,
            COALESCE(cu.full_name, g.customer_name) AS customer_name,
            COALESCE(p.full_name, g.profile_name) AS profile_name
       FROM gift_codes g
       LEFT JOIN customers cu ON cu.id = g.customer_id
       LEFT JOIN profiles p ON p.id = g.profile_id
      WHERE g.agent_id = $1
      ORDER BY (g.status = 'used'), CASE WHEN g.status = 'unused' THEN g.id END,
               g.used_at DESC NULLS LAST, g.id DESC`,
    [agent.id],
  );
  return rows.map((r) => ({
    id: r.id,
    code: r.code,
    status: r.status,
    created_at: r.created_at,
    used_at: r.used_at ?? null,
    customer: r.customer_name ? { id: r.customer_id ?? null, full_name: r.customer_name } : null,
    profile: r.profile_name ? { id: r.profile_id ?? null, full_name: r.profile_name } : null,
    share_text: giftShareText(r.code, agent),
  }));
}

/** 409 while a UPI claim for the profile waits for an admin (money may be on its way). */
async function assertNoUpiUnderReview(client, profileId) {
  const { rows } = await client.query(
    `SELECT 1 FROM payments WHERE profile_id = $1 AND provider = 'upi' AND status = 'submitted' LIMIT 1`,
    [profileId],
  );
  if (rows.length) {
    throw conflict('payment_under_review', 'Your payment is being verified — a gift code is not needed now');
  }
}

/**
 * Spends the locked, unused code `code` on the locked, unpaid customer profile
 * (all inside the caller's transaction): a 'gift' payment, the profile paid and
 * live, the customer active (approved by the code's agent — the code is the
 * approval), the code used. The customer must already belong to the code's
 * agent. Returns the payments row.
 */
async function spendGiftCode(client, { code, customer, profile }) {
  const { rows: pay } = await client.query(
    `INSERT INTO payments (customer_id, profile_id, amount_paise, currency, provider, status, paid_at, recorded_by, note)
     VALUES ($1, $2, 0, 'INR', 'gift', 'paid', now(), $3, $4) RETURNING *`,
    [customer.id, profile.id, code.agent_id, `gift code ${code.code}`],
  );
  await client.query(
    `UPDATE customers
        SET status = 'active', approved_by = COALESCE(approved_by, $2),
            approved_at = COALESCE(approved_at, now()), updated_at = now()
      WHERE id = $1`,
    [customer.id, code.agent_id],
  );
  await client.query(
    `UPDATE profiles SET paid_at = now(), updated_at = now(),
            status = CASE WHEN status = 'hidden' THEN 'active' ELSE status END
      WHERE id = $1`,
    [profile.id],
  );
  await client.query(
    `UPDATE gift_codes SET status = 'used', used_at = now(), customer_id = $2, profile_id = $3,
            payment_id = $4, customer_name = $5, profile_name = $6
      WHERE id = $1`,
    [code.id, customer.id, profile.id, pay[0].id, customer.full_name, profile.full_name],
  );
  return pay[0];
}

async function lockOwnUnpaidProfile(client, customerId, profileId) {
  const { rows } = await client.query(
    'SELECT id, full_name, paid_at FROM profiles WHERE id = $1 AND customer_id = $2 FOR UPDATE',
    [profileId, customerId],
  );
  const profile = rows[0];
  if (!profile) throw notFound('profile_not_found', 'Profile not found');
  if (profile.paid_at) throw conflict('already_paid', 'This profile is already paid for');
  await assertNoUpiUnderReview(client, profileId);
  return profile;
}

async function assertAgentCanTakeCustomers(client, code) {
  if (code.agent_status !== 'active') {
    throw badRequest('agent_not_active', "This agent's account is not active — check with your agent");
  }
  const { rows } = await client.query('SELECT 1 FROM agent_communities WHERE agent_id = $1 LIMIT 1', [code.agent_id]);
  if (!rows.length) throw badRequest('agent_has_no_communities', 'This agent cannot take customers — check with your agent');
}

const CODE_SELECT = `SELECT g.id, g.code, g.status, g.agent_id, a.status AS agent_status, a.is_demo AS agent_demo
                       FROM gift_codes g JOIN agents a ON a.id = g.agent_id`;

/**
 * A customer redeems `codeText` for their own profile `profileId` (SPEC §9.23
 * B), inside `client`'s transaction. A guest / pending / rejected customer is
 * moved to the code's agent first. Throws the documented errors; `invalid`
 * on the thrown error marks a wrong code (for the attempt limiter).
 * Returns {agentId}.
 */
export async function redeemGiftCodeAsCustomer(client, { customerId, profileId, codeText }) {
  const wrong = () => {
    const e = notFound('gift_code_not_found', 'This gift code is not valid — check it with your agent');
    e.invalid = true;
    return e;
  };
  const normalised = normaliseGiftCode(codeText);
  if (!normalised) throw wrong();

  const { rows: cus } = await client.query(
    'SELECT id, full_name, status, agent_id, is_demo FROM customers WHERE id = $1 FOR UPDATE',
    [customerId],
  );
  const customer = cus[0];
  if (!customer) throw notFound('customer_not_found', 'Account not found');
  const profile = await lockOwnUnpaidProfile(client, customer.id, profileId);

  const { rows: codes } = await client.query(`${CODE_SELECT} WHERE g.code = $1 FOR UPDATE OF g`, [normalised]);
  const code = codes[0];
  // A code of the other world (SPEC §9.21) does not exist for this customer.
  if (!code || Boolean(code.agent_demo) !== Boolean(customer.is_demo)) throw wrong();
  if (code.status !== 'unused') throw conflict('gift_code_used', 'This gift code has already been used');
  await assertAgentCanTakeCustomers(client, code);

  if (customer.agent_id !== code.agent_id) {
    if (customer.status === 'active') {
      throw conflict('gift_code_other_agent', 'This code is from another agent. Ask your agent for a code.');
    }
    if (customer.status === 'suspended') throw conflict('wrong_status', 'Your account has been suspended');
    // Guest / pending / rejected: simply move to the code's agent, profile and all.
    await client.query(`UPDATE customers SET agent_id = $2, updated_at = now() WHERE id = $1`, [
      customer.id,
      code.agent_id,
    ]);
    await client.query('UPDATE profiles SET uploaded_by = $2, updated_at = now() WHERE customer_id = $1', [
      customer.id,
      code.agent_id,
    ]);
    await issueMissingProfileCodes(client, { customerId: customer.id });
  }
  await spendGiftCode(client, { code, customer, profile });
  return { agentId: code.agent_id };
}

/**
 * The client's agent (or an admin) spends one of that agent's codes on the
 * client's unpaid profile — `codeText` or the oldest unused one. Inside
 * `client`'s transaction. Returns {agentId}.
 */
export async function applyGiftCodeForClient(client, { customerId, profileId, codeText = null }) {
  const { rows: cus } = await client.query(
    'SELECT id, full_name, status, agent_id FROM customers WHERE id = $1 FOR UPDATE',
    [customerId],
  );
  const customer = cus[0];
  if (!customer) throw notFound('client_not_found', 'Client not found');
  if (!customer.agent_id) throw conflict('wrong_status', 'This customer has no agent yet');
  if (customer.status === 'suspended') throw conflict('wrong_status', 'This client is suspended');
  const profile = await lockOwnUnpaidProfile(client, customer.id, profileId);

  let code;
  if (codeText) {
    const normalised = normaliseGiftCode(codeText);
    const { rows } = normalised
      ? await client.query(`${CODE_SELECT} WHERE g.code = $1 AND g.agent_id = $2 FOR UPDATE OF g`, [
          normalised,
          customer.agent_id,
        ])
      : { rows: [] };
    code = rows[0];
    if (!code) throw notFound('gift_code_not_found', 'This is not one of your gift codes');
    if (code.status !== 'unused') throw conflict('gift_code_used', 'This gift code has already been used');
  } else {
    const { rows } = await client.query(
      `${CODE_SELECT} WHERE g.agent_id = $1 AND g.status = 'unused' ORDER BY g.id LIMIT 1 FOR UPDATE OF g SKIP LOCKED`,
      [customer.agent_id],
    );
    code = rows[0];
    if (!code) throw conflict('no_gift_codes', 'You have no gift codes left — ask the admin for more');
  }
  await spendGiftCode(client, { code, customer, profile });
  return { agentId: code.agent_id };
}
