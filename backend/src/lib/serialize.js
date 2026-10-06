/** Public shape of an agent. Never leaks password_hash or the registration token. */
export function agentPublic(agent, communities) {
  return {
    id: agent.id,
    full_name: agent.full_name,
    phone: agent.phone,
    agency_name: agent.agency_name,
    city: agent.city ?? null,
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
 * business details only.
 */
export function agentDirectory(agent, communities) {
  return {
    id: agent.id,
    full_name: agent.full_name,
    agency_name: agent.agency_name,
    city: agent.city ?? null,
    phone: agent.phone,
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
