/**
 * The agent columns every "who am I" response needs, with the state joined
 * (SPEC §9.18 B). Never the password hash. Alias `a`; append a WHERE on a.*.
 */
export const AGENT_SELECT = `
  SELECT a.id, a.full_name, a.phone, a.agency_name, a.role, a.status,
         a.must_change_password, a.city, a.registration_token, a.created_at,
         a.state_id, a.agent_code, st.name AS state_name, st.code AS state_code
    FROM agents a
    LEFT JOIN states st ON st.id = a.state_id`;

/** Public shape of an agent. Never leaks password_hash or the registration token. */
export function agentPublic(agent, communities) {
  return {
    id: agent.id,
    full_name: agent.full_name,
    phone: agent.phone,
    agency_name: agent.agency_name,
    city: agent.city ?? null,
    // SPEC §9.18 B: the state the agent chose (once) and their permanent code.
    state: agent.state_id ? { id: agent.state_id, name: agent.state_name, code: agent.state_code } : null,
    agent_code: agent.agent_code ?? null,
    role: agent.role,
    status: agent.status,
    // True after an admin issued a temporary password (forgot-password flow).
    must_change_password: Boolean(agent.must_change_password),
    created_at: agent.created_at,
    ...(communities ? { communities } : {}),
  };
}

/**
 * An agent as customers see them (SPEC §9.6 directory, the "my agent" card):
 * business details only. The agent code is one of them (SPEC §9.18 B) — a
 * customer can link their agent by it.
 */
export function agentDirectory(agent, communities) {
  return {
    id: agent.id,
    full_name: agent.full_name,
    agency_name: agent.agency_name,
    city: agent.city ?? null,
    phone: agent.phone,
    agent_code: agent.agent_code ?? null,
    ...(communities ? { communities } : {}),
  };
}

/** Public shape of a customer (SPEC §9.2). `agent` is agentDirectory() when given. */
export function customerPublic(customer, { agent, profileId, pendingAgentChange } = {}) {
  return {
    id: customer.id,
    full_name: customer.full_name,
    phone: customer.phone,
    status: customer.status,
    source: customer.source,
    phone_verified_at: customer.phone_verified_at ?? null,
    approved_at: customer.approved_at ?? null,
    created_at: customer.created_at,
    ...(agent !== undefined ? { agent } : {}),
    ...(profileId !== undefined ? { profile_id: profileId, has_profile: profileId != null } : {}),
    ...(pendingAgentChange !== undefined ? { pending_agent_change: pendingAgentChange } : {}),
  };
}
