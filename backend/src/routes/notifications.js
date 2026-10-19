import { Router } from 'express';
import { many } from '../lib/db.js';
import { asyncHandler } from '../lib/errors.js';

export const notificationsRouter = Router();

/**
 * GET /api/notifications — v1 is in-app polling (SPEC §4).
 * Streams: requests waiting on my uploads, decisions on requests I sent,
 * decisions on my community-change requests, the hold workflow, and (SPEC
 * §9.10) customers awaiting my approval, interests on my uploads, decisions
 * on my clients' interests, and agent transfers. Admins also see pending
 * agents and password resets.
 */
notificationsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await agentFeed(req.agent));
  }),
);

/**
 * The agent's feed {badge, counts, items} — also what the push sender
 * (lib/pushWorker.js, SPEC §9.16) diffs. `agent` needs id and is_admin.
 */
export async function agentFeed(agent) {
  const req = { agent };
  {
    const me = req.agent.id;

    const inboxSql = req.agent.is_admin
      ? `SELECT cr.id, cr.profile_id, cr.requested_at, p.full_name, a.full_name AS requester_name
           FROM contact_requests cr
           JOIN profiles p ON p.id = cr.profile_id
           JOIN agents a ON a.id = cr.requester_id
          WHERE cr.status = 'pending'
          ORDER BY cr.requested_at DESC LIMIT 50`
      : `SELECT cr.id, cr.profile_id, cr.requested_at, p.full_name, a.full_name AS requester_name
           FROM contact_requests cr
           JOIN profiles p ON p.id = cr.profile_id
           JOIN agents a ON a.id = cr.requester_id
          WHERE cr.status = 'pending' AND p.uploaded_by = $1
          ORDER BY cr.requested_at DESC LIMIT 50`;

    // Hold requests waiting on my uploads (admin: all) — the approver must act.
    const holdInboxSql = `SELECT h.id, h.profile_id, h.requested_at, p.full_name, a.full_name AS requester_name
           FROM hold_requests h
           JOIN profiles p ON p.id = h.profile_id
           JOIN agents a ON a.id = h.requester_id
          WHERE h.status = 'pending' ${req.agent.is_admin ? '' : 'AND p.uploaded_by = $1'}
          ORDER BY h.requested_at DESC LIMIT 50`;

    // SPEC §9.10 — customers, interests and agent transfers. "Mine" means my
    // clients / my uploads / my outgoing transfers; admins see every inbox.
    const mineOr = (col) => (req.agent.is_admin ? '' : `AND ${col} = $1`);
    const inboxParams = req.agent.is_admin ? [] : [me];

    const [
      inbox, decisions, communityDecisions, pendingAgents, pendingResets, holdInbox, holdDecisions,
      pendingClients, interestInbox, interestDecisions, changeInbox, changeDecided, deleteInbox,
    ] = await Promise.all([
      many(inboxSql, req.agent.is_admin ? [] : [me]),
      many(
        `SELECT cr.id, cr.profile_id, cr.status, cr.decided_at, cr.expires_at, p.full_name
           FROM contact_requests cr JOIN profiles p ON p.id = cr.profile_id
          WHERE cr.requester_id = $1 AND cr.decided_at IS NOT NULL
          ORDER BY cr.decided_at DESC LIMIT 20`,
        [me],
      ),
      many(
        `SELECT ccr.id, ccr.status, ccr.decided_at, c.name AS community_name
           FROM community_change_requests ccr JOIN communities c ON c.id = ccr.community_id
          WHERE ccr.agent_id = $1 AND ccr.status <> 'pending'
          ORDER BY ccr.decided_at DESC LIMIT 20`,
        [me],
      ),
      req.agent.is_admin
        ? many(`SELECT id, full_name, created_at FROM agents WHERE status = 'pending' ORDER BY created_at DESC LIMIT 50`)
        : Promise.resolve([]),
      req.agent.is_admin
        ? many(
            `SELECT prr.id, prr.requested_at, a.full_name, a.phone
               FROM password_reset_requests prr JOIN agents a ON a.id = prr.agent_id
              WHERE prr.status = 'pending' ORDER BY prr.requested_at DESC LIMIT 50`,
          )
        : Promise.resolve([]),
      many(holdInboxSql, req.agent.is_admin ? [] : [me]),
      many(
        `SELECT h.id, h.profile_id, h.status, h.decided_at, h.released_at, p.full_name
           FROM hold_requests h JOIN profiles p ON p.id = h.profile_id
          WHERE h.requester_id = $1 AND h.status IN ('approved', 'rejected', 'released')
            AND COALESCE(h.released_at, h.decided_at) IS NOT NULL
          ORDER BY COALESCE(h.released_at, h.decided_at) DESC LIMIT 20`,
        [me],
      ),
      // Customers waiting for my approval (SPEC §9.5).
      many(
        `SELECT cu.id, cu.full_name, cu.source, cu.created_at
           FROM customers cu
          WHERE cu.status = 'pending' ${mineOr('cu.agent_id')}
          ORDER BY cu.created_at DESC LIMIT 50`,
        inboxParams,
      ),
      // Pending interests on my uploads — I decide them (SPEC §9.4).
      many(
        `SELECT ci.id, ci.profile_id, ci.customer_id, ci.created_at,
                cu.full_name AS customer_name, p.full_name AS profile_name
           FROM customer_interests ci
           JOIN customers cu ON cu.id = ci.customer_id
           JOIN profiles p ON p.id = ci.profile_id
          WHERE ci.status = 'pending' ${mineOr('p.uploaded_by')}
          ORDER BY ci.created_at DESC LIMIT 50`,
        inboxParams,
      ),
      // Decisions on my clients' interests.
      many(
        `SELECT ci.id, ci.profile_id, ci.customer_id, ci.status, ci.decided_at,
                cu.full_name AS customer_name, p.full_name AS profile_name
           FROM customer_interests ci
           JOIN customers cu ON cu.id = ci.customer_id
           JOIN profiles p ON p.id = ci.profile_id
          WHERE cu.agent_id = $1 AND ci.status IN ('accepted', 'declined', 'revoked') AND ci.decided_at IS NOT NULL
          ORDER BY ci.decided_at DESC LIMIT 20`,
        [me],
      ),
      // My clients asking to move to another agent — needs my decision (SPEC §9.6).
      many(
        `SELECT r.id, r.customer_id, r.created_at, cu.full_name AS customer_name,
                ta.full_name AS to_agent_name, ta.agency_name AS to_agent_agency
           FROM agent_change_requests r
           JOIN customers cu ON cu.id = r.customer_id
           JOIN agents ta ON ta.id = r.to_agent_id
          WHERE r.status = 'pending' ${mineOr('r.from_agent_id')}
          ORDER BY r.created_at DESC LIMIT 50`,
        inboxParams,
      ),
      // Customers who moved to me.
      many(
        `SELECT r.id, r.customer_id, r.decided_at, cu.full_name AS customer_name,
                fa.full_name AS from_agent_name, fa.agency_name AS from_agent_agency
           FROM agent_change_requests r
           JOIN customers cu ON cu.id = r.customer_id
           JOIN agents fa ON fa.id = r.from_agent_id
          WHERE r.status = 'approved' AND r.to_agent_id = $1 AND r.decided_at IS NOT NULL
          ORDER BY r.decided_at DESC LIMIT 20`,
        [me],
      ),
      // My clients asking to delete a paid profile — needs my decision (SPEC §9.13).
      many(
        `SELECT d.id, d.customer_id, d.profile_id, d.profile_name, d.created_at, cu.full_name AS customer_name
           FROM profile_delete_requests d
           JOIN customers cu ON cu.id = d.customer_id
          WHERE d.status = 'pending' ${mineOr('cu.agent_id')}
          ORDER BY d.created_at DESC LIMIT 50`,
        inboxParams,
      ),
    ]);

    const items = [
      ...inbox.map((r) => ({
        type: 'contact_request_received',
        id: r.id,
        profile_id: r.profile_id,
        title: 'Contact request',
        body: `${r.requester_name} wants contact details for ${r.full_name}`,
        at: r.requested_at,
      })),
      ...decisions.map((r) => ({
        type: 'contact_request_decided',
        id: r.id,
        profile_id: r.profile_id,
        title: `Request ${r.status}`,
        body: `Your request for ${r.full_name} was ${r.status}`,
        at: r.decided_at,
      })),
      ...communityDecisions.map((r) => ({
        type: 'community_request_decided',
        id: r.id,
        title: `Community request ${r.status}`,
        body: `Your request to join ${r.community_name} was ${r.status}`,
        at: r.decided_at,
      })),
      ...pendingAgents.map((r) => ({
        type: 'agent_pending',
        id: r.id,
        title: 'New agent awaiting approval',
        body: r.full_name,
        at: r.created_at,
      })),
      ...pendingResets.map((r) => ({
        type: 'password_reset_requested',
        id: r.id,
        title: 'Password reset requested',
        body: `${r.full_name} (+91 ${r.phone}) forgot their password`,
        at: r.requested_at,
      })),
      ...holdInbox.map((r) => ({
        type: 'hold_request_received',
        id: r.id,
        profile_id: r.profile_id,
        title: 'Hold request',
        body: `${r.requester_name} wants to put ${r.full_name} on hold`,
        at: r.requested_at,
      })),
      ...holdDecisions.map((r) => ({
        type: 'hold_request_decided',
        id: r.id,
        profile_id: r.profile_id,
        title: `Hold ${r.status}`,
        body: `Your hold on ${r.full_name} was ${r.status}`,
        at: r.released_at ?? r.decided_at,
      })),
      // ---- SPEC §9.10
      ...pendingClients.map((r) => ({
        type: 'client_pending',
        id: r.id,
        customer_id: r.id,
        title: 'New client awaiting approval',
        body: `${r.full_name} registered ${r.source === 'form' ? 'through your form' : 'in the MILI app'}`,
        at: r.created_at,
      })),
      ...interestInbox.map((r) => ({
        type: 'interest_received',
        id: r.id,
        profile_id: r.profile_id,
        customer_id: r.customer_id,
        title: 'New interest',
        body: `${r.customer_name} is interested in ${r.profile_name}`,
        at: r.created_at,
      })),
      ...interestDecisions.map((r) => ({
        type: 'interest_decided',
        id: r.id,
        profile_id: r.profile_id,
        customer_id: r.customer_id,
        title: `Interest ${r.status}`,
        body: `${r.customer_name}'s interest in ${r.profile_name} was ${r.status}`,
        at: r.decided_at,
      })),
      ...changeInbox.map((r) => ({
        type: 'agent_change_requested',
        id: r.id,
        customer_id: r.customer_id,
        title: 'Client wants to change agent',
        body: `${r.customer_name} asked to move to ${r.to_agent_name}${r.to_agent_agency ? ` (${r.to_agent_agency})` : ''}`,
        at: r.created_at,
      })),
      ...changeDecided.map((r) => ({
        type: 'agent_change_decided',
        id: r.id,
        customer_id: r.customer_id,
        title: 'New client',
        body: `${r.customer_name} is now your client (moved from ${r.from_agent_name}${r.from_agent_agency ? `, ${r.from_agent_agency}` : ''})`,
        at: r.decided_at,
      })),
      ...deleteInbox.map((r) => ({
        type: 'profile_delete_requested',
        id: r.id,
        customer_id: r.customer_id,
        profile_id: r.profile_id,
        title: 'Profile delete request',
        body: `${r.customer_name} asked to delete the profile ${r.profile_name}`,
        at: r.created_at,
      })),
    ].sort((a, b) => new Date(b.at) - new Date(a.at));

    return {
      // Badge count = things that need an action from me.
      badge:
        inbox.length + holdInbox.length + pendingAgents.length + pendingResets.length +
        pendingClients.length + interestInbox.length + changeInbox.length + deleteInbox.length,
      counts: {
        contact_requests_inbox: inbox.length,
        hold_requests_inbox: holdInbox.length,
        pending_agents: pendingAgents.length,
        pending_password_resets: pendingResets.length,
        // Clients tab badge = these four (SPEC §9.10 / §9.13).
        pending_clients: pendingClients.length,
        interests_inbox: interestInbox.length,
        agent_change_inbox: changeInbox.length,
        delete_requests_inbox: deleteInbox.length,
      },
      items,
    };
  }
}
