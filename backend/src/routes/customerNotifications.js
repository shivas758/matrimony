// Gandharva notifications — SPEC §9.15. Mounted at /api/customer/notifications
// behind requireCustomer (any status: guests get payment reminders, rejected
// customers learn why they are stuck).
//
// Everything is derived from existing rows; there is no read state on the
// server (the app keeps a per-device "last opened" timestamp). Bodies name
// profiles and the customer's OWN agent only — never the uploader of someone
// else's profile (CLAUDE.md rule 7).
import { Router } from 'express';
import { many, one } from '../lib/db.js';
import { asyncHandler } from '../lib/errors.js';

export const customerNotificationsRouter = Router();

const EXPIRY_WARNING_DAYS = 3;
const HISTORY_LIMIT = 30;

const INTEREST_TITLES = {
  accepted: 'Details shared with you',
  declined: 'Interest declined',
  revoked: 'Details no longer shared',
};

customerNotificationsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await customerFeed(req.customer.id));
  }),
);

/** The customer's feed {action_count, items} — also diffed by the push sender (SPEC §9.16). */
export async function customerFeed(me) {
  {

    const [account, unpaid, expiring, interests, payments, changes, deletes] = await Promise.all([
      one(
        `SELECT cu.status, cu.approved_at, cu.updated_at, a.full_name AS agent_name
           FROM customers cu LEFT JOIN agents a ON a.id = cu.agent_id WHERE cu.id = $1`,
        [me],
      ),
      many(
        `SELECT id, full_name, created_at FROM profiles
          WHERE customer_id = $1 AND paid_at IS NULL ORDER BY created_at, id`,
        [me],
      ),
      many(
        `SELECT ci.id, ci.profile_id, ci.access_expires_at, p.full_name,
                CEIL(EXTRACT(EPOCH FROM (ci.access_expires_at - now())) / 86400)::int AS days_left
           FROM customer_interests ci JOIN profiles p ON p.id = ci.profile_id
          WHERE ci.customer_id = $1 AND ci.status = 'accepted'
            AND ci.access_expires_at > now()
            AND ci.access_expires_at <= now() + make_interval(days => $2)
          ORDER BY ci.access_expires_at`,
        [me, EXPIRY_WARNING_DAYS],
      ),
      many(
        `SELECT ci.id, ci.profile_id, ci.from_profile_id, ci.status, ci.decided_at, p.full_name,
                fp.full_name AS from_name
           FROM customer_interests ci
           JOIN profiles p ON p.id = ci.profile_id
           LEFT JOIN profiles fp ON fp.id = ci.from_profile_id
          WHERE ci.customer_id = $1 AND ci.status IN ('accepted','declined','revoked') AND ci.decided_at IS NOT NULL
          ORDER BY ci.decided_at DESC LIMIT $2`,
        [me, HISTORY_LIMIT],
      ),
      many(
        `SELECT pay.id, pay.profile_id, pay.provider, pay.amount_paise, pay.paid_at, p.full_name
           FROM payments pay LEFT JOIN profiles p ON p.id = pay.profile_id
          WHERE pay.customer_id = $1 AND pay.status = 'paid' AND pay.provider <> 'waived'
          ORDER BY pay.paid_at DESC LIMIT $2`,
        [me, HISTORY_LIMIT],
      ),
      many(
        `SELECT r.id, r.status, r.decided_at, ta.full_name AS to_agent_name
           FROM agent_change_requests r JOIN agents ta ON ta.id = r.to_agent_id
          WHERE r.customer_id = $1 AND r.status IN ('approved','rejected') AND r.decided_at IS NOT NULL
          ORDER BY r.decided_at DESC LIMIT $2`,
        [me, HISTORY_LIMIT],
      ),
      many(
        `SELECT id, profile_id, profile_name, status, decided_at FROM profile_delete_requests
          WHERE customer_id = $1 AND status IN ('approved','rejected') AND decided_at IS NOT NULL
          ORDER BY decided_at DESC LIMIT $2`,
        [me, HISTORY_LIMIT],
      ),
    ]);

    const action = [
      ...unpaid.map((p) => ({
        type: 'payment_due',
        id: p.id,
        my_profile_id: p.id,
        title: 'Registration fee due',
        body: `Pay the registration fee for ${p.full_name} so others can see the profile`,
        at: p.created_at,
      })),
      ...expiring.map((r) => ({
        type: 'interest_expiring',
        id: r.id,
        interest_id: r.id,
        profile_id: r.profile_id,
        title: 'Shared details ending soon',
        body: `You can see ${r.full_name}'s details for ${r.days_left} more day${r.days_left === 1 ? '' : 's'}`,
        at: r.access_expires_at,
      })),
    ];

    const updates = [];
    if (account?.approved_at) {
      updates.push({
        type: 'account_approved',
        id: me,
        title: 'Account approved',
        body: `${account.agent_name ?? 'Your agent'} approved your account`,
        at: account.approved_at,
      });
    }
    if (account?.status === 'rejected') {
      updates.push({
        type: 'account_rejected',
        id: me,
        title: 'Not approved',
        body: `${account.agent_name ?? 'Your agent'} did not approve your account — you can choose another agent`,
        at: account.updated_at,
      });
    }
    updates.push(
      ...interests.map((r) => ({
        type: `interest_${r.status}`,
        id: r.id,
        interest_id: r.id,
        profile_id: r.profile_id,
        my_profile_id: r.from_profile_id ?? undefined,
        title: INTEREST_TITLES[r.status],
        body:
          r.status === 'accepted'
            ? `${r.full_name}'s family shared their details${r.from_name ? ` (for ${r.from_name})` : ''} — your agent will follow up`
            : r.status === 'declined'
              ? `Your interest in ${r.full_name} was declined`
              : `${r.full_name}'s details are no longer shared with you`,
        at: r.decided_at,
      })),
      ...payments.map((r) => ({
        type: 'payment_received',
        id: r.id,
        my_profile_id: r.profile_id ?? undefined,
        title: 'Payment received',
        body: `₹${r.amount_paise / 100} ${r.provider === 'cash' ? 'received in cash by your agent' : 'paid'}${
          r.full_name ? ` for ${r.full_name}` : ''
        }`,
        at: r.paid_at,
      })),
      ...changes.map((r) => ({
        type: `agent_change_${r.status}`,
        id: r.id,
        title: r.status === 'approved' ? 'Agent changed' : 'Agent change declined',
        body:
          r.status === 'approved'
            ? `${r.to_agent_name} is now your agent`
            : `Your request to move to ${r.to_agent_name} was declined`,
        at: r.decided_at,
      })),
      ...deletes.map((r) => ({
        type: `delete_request_${r.status}`,
        id: r.id,
        my_profile_id: r.status === 'rejected' ? r.profile_id ?? undefined : undefined,
        title: r.status === 'approved' ? 'Profile deleted' : 'Delete request declined',
        body:
          r.status === 'approved'
            ? `${r.profile_name} was deleted`
            : `Your agent kept ${r.profile_name} — call them if you still want it removed`,
        at: r.decided_at,
      })),
    );

    const byDate = (a, b) => new Date(b.at) - new Date(a.at);
    return {
      action_count: action.length,
      items: [
        ...action.sort(byDate).map((i) => ({ ...i, group: 'action' })),
        ...updates.sort(byDate).map((i) => ({ ...i, group: 'update' })),
      ],
    };
  }
}
