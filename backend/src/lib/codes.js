// Agent codes and customer / profile IDs — SPEC §9.18 B and C.
//
//   agent code   STATE + NUMBER + LETTER(S), per state, in issue order:
//                KA1A … KA1Z, KA2A … KA999Z, then KA1AA … KA999ZZ, then three letters.
//   profile ID   GN-<agent code>-<LETTER(S)><3 digits>, per agent:
//                GN-KA1A-A001 … A999, B001 … Z999, then AA001 …
//
// Both are permanent. The sequences (agent_code_counters.last_seq per state,
// agents.profile_seq per agent) only ever count up, so a code is never issued
// twice — also not after the agent or the profile it belonged to is deleted.
// Every function here takes a pg client INSIDE a transaction: a rolled-back
// transaction takes its counter increment back with it, a committed one never
// shares a number.

const A = 'A'.charCodeAt(0);
const NUMBERS = 999;

/** `index` (0-based) as `width` letters, base 26: 0 → A / AA, 25 → Z / AZ, 26 → BA. */
function letters(index, width) {
  let out = '';
  let rest = index;
  for (let i = 0; i < width; i++) {
    out = String.fromCharCode(A + (rest % 26)) + out;
    rest = Math.floor(rest / 26);
  }
  return out;
}

function assertSequence(n) {
  if (!Number.isInteger(n) || n < 1) throw new Error(`bad code sequence ${n}`);
}

/** The n-th (1-based) agent code of a state: agentCodeFor('KA', 27) → 'KA2A'. */
export function agentCodeFor(stateCode, n) {
  assertSequence(n);
  let rest = n - 1;
  for (let width = 1; ; width++) {
    const perNumber = 26 ** width;
    const capacity = NUMBERS * perNumber;
    if (rest < capacity) {
      return `${stateCode}${Math.floor(rest / perNumber) + 1}${letters(rest % perNumber, width)}`;
    }
    rest -= capacity;
  }
}

/** The n-th (1-based) profile ID of an agent: profileCodeFor('KA1A', 1000) → 'GN-KA1A-B001'. */
export function profileCodeFor(agentCode, n) {
  assertSequence(n);
  let rest = n - 1;
  for (let width = 1; ; width++) {
    const capacity = 26 ** width * NUMBERS;
    if (rest < capacity) {
      const serial = String((rest % NUMBERS) + 1).padStart(3, '0');
      return `GN-${agentCode}-${letters(Math.floor(rest / NUMBERS), width)}${serial}`;
    }
    rest -= capacity;
  }
}

/** The active state behind an id, or null. */
export async function findState(client, stateId) {
  const { rows } = await client.query('SELECT id, name, code FROM states WHERE id = $1 AND active = TRUE', [stateId]);
  return rows[0] ?? null;
}

/**
 * Gives an agent their state and the next code of that state. The caller has
 * checked that the agent has no code yet and that `state` (findState) exists.
 * Returns the code.
 */
export async function issueAgentCode(client, agentId, state) {
  const { rows } = await client.query(
    `INSERT INTO agent_code_counters (state_id, last_seq) VALUES ($1, 1)
     ON CONFLICT (state_id) DO UPDATE SET last_seq = agent_code_counters.last_seq + 1
     RETURNING last_seq`,
    [state.id],
  );
  const code = agentCodeFor(state.code, rows[0].last_seq);
  await client.query('UPDATE agents SET state_id = $2, agent_code = $3 WHERE id = $1', [agentId, state.id, code]);
  return code;
}

/**
 * Gives a profile its ID from its agent's (uploaded_by) sequence. A profile
 * that already has one keeps it — the ID never changes, not on an agent
 * change either. Returns the ID, or null while the agent has no code yet.
 */
export async function issueProfileCode(client, profileId) {
  const { rows } = await client.query(
    'SELECT id, uploaded_by, profile_code FROM profiles WHERE id = $1 FOR UPDATE',
    [profileId],
  );
  const profile = rows[0];
  if (!profile) return null;
  if (profile.profile_code) return profile.profile_code;

  const bumped = await client.query(
    `UPDATE agents SET profile_seq = profile_seq + 1
      WHERE id = $1 AND agent_code IS NOT NULL
      RETURNING profile_seq, agent_code`,
    [profile.uploaded_by],
  );
  const agent = bumped.rows[0];
  if (!agent) return null;
  const code = profileCodeFor(agent.agent_code, agent.profile_seq);
  await client.query('UPDATE profiles SET profile_code = $2 WHERE id = $1', [profileId, code]);
  return code;
}

/**
 * IDs for every profile that still lacks one, oldest first — all uploads of an
 * agent who just got their code (`agentId`), or the profiles of a customer who
 * just linked / moved to an agent (`customerId`).
 */
export async function issueMissingProfileCodes(client, { agentId = null, customerId = null }) {
  const { rows } = await client.query(
    `SELECT id FROM profiles
      WHERE profile_code IS NULL
        AND (($1::int IS NOT NULL AND uploaded_by = $1) OR ($2::int IS NOT NULL AND customer_id = $2))
      ORDER BY created_at, id`,
    [agentId, customerId],
  );
  for (const row of rows) await issueProfileCode(client, row.id);
  return rows.length;
}
