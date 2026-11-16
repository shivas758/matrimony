// The Wedbook Matrimony registration fee — SPEC §9.12 / §9.19 B. One payment
// per customer profile; a profile is visible to others only when it is paid
// AND its customer is active.
//
// Provider is chosen by env (see .env.example), no code change to switch:
//   PAYMENT_PROVIDER=mock      (default) nothing is charged; confirm succeeds
//                              unless the app asks for outcome 'failure'.
//   PAYMENT_PROVIDER=razorpay  RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET; orders are
//                              created through Razorpay's Orders API, confirm
//                              checks the Checkout signature (HMAC-SHA256 of
//                              "order_id|payment_id") and captures the payment
//                              if the account is on manual capture.
//   RAZORPAY_WEBHOOK_SECRET    optional: POST /api/payments/razorpay/webhook
//                              settles order.paid / payment.captured events.
//   PAYMENT_PROVIDER=upi       UPI_PAYEE_VPA (+ UPI_PAYEE_NAME): the payer pays the
//                              owner's UPI ID from any UPI app, submits the UTR,
//                              and an admin verifies it (SPEC §9.20). The agents'
//                              extra-community fee always works this way.
//
// Every route that learns "this order is paid" (confirm, the safety net in
// createProfilePayment, the webhook) goes through settle(), so a payment is
// counted once and a profile is never paid twice (a second payment becomes
// 'refund_due' — refund it from the Razorpay dashboard).
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { many, one, tx } from './db.js';
import { ApiError, badRequest, conflict, notFound } from './errors.js';
import { refreshAgentApproval } from './agentApproval.js';

/** A client's profile may just have gone live: their agent may now be approved (SPEC §9.23 A). */
async function refreshUploaderApproval(client, profileId) {
  const { rows } = await client.query('SELECT uploaded_by FROM profiles WHERE id = $1', [profileId]);
  await refreshAgentApproval(rows[0]?.uploaded_by ?? null, client);
}

export const feePaise = () => Math.round(config.payments.profileFeeInr * 100);
export const communityFeePaise = () => Math.round(config.communities.extraFeeInr * 100);

// ---- direct UPI (SPEC §9.20) -------------------------------------------------

export const upiReady = () => Boolean(config.payments.upi.vpa);
const upiNotReady = () => new ApiError(503, 'payment_provider_error', 'UPI payments are not set up yet');

/** What the apps need to pay a UPI payment row: payee, amount, reference and the upi:// link. */
export function upiBlock(row) {
  if (!row || row.provider !== 'upi') return null;
  const { vpa, name } = config.payments.upi;
  const reference = `WB${row.id}`;
  const note = `Wedbook ${reference}`;
  const amount = (row.amount_paise / 100).toFixed(2);
  // No `tr`: several UPI apps refuse it for non-merchant payee IDs.
  const uri = `upi://pay?pa=${vpa}&pn=${encodeURIComponent(name)}&am=${amount}&cu=INR&tn=${encodeURIComponent(note)}`;
  return { vpa, name, amount_inr: row.amount_paise / 100, note, reference, uri };
}

/** Wire shape of a payments row (never the provider secret). */
export function paymentPublic(row) {
  if (!row) return null;
  return {
    id: row.id,
    purpose: row.purpose ?? 'profile_registration',
    profile_id: row.profile_id,
    status: row.status,
    amount_paise: row.amount_paise,
    amount_inr: row.amount_paise / 100,
    currency: row.currency,
    provider: row.provider,
    order_id: row.provider_order_id,
    // Razorpay Checkout needs the public key id; mock has none.
    key_id: row.provider === 'razorpay' ? config.payments.razorpay.keyId : null,
    utr: row.utr ?? null,
    submitted_at: row.submitted_at ?? null,
    verified_at: row.verified_at ?? null,
    reject_reason: row.reject_reason ?? null,
    upi: upiBlock(row),
    created_at: row.created_at,
    paid_at: row.paid_at ?? null,
  };
}

/** The open UPI payment of an unpaid profile (created / submitted / rejected), for the owner's view. */
export async function profileUpiState(profileId) {
  return one(
    `SELECT id, status, utr, submitted_at, reject_reason FROM payments
      WHERE profile_id = $1 AND provider = 'upi' AND purpose = 'profile_registration'
        AND status IN ('created','submitted','failed')
      ORDER BY id DESC LIMIT 1`,
    [profileId],
  );
}

// ---- Razorpay REST -----------------------------------------------------------

const razorpayReady = () => Boolean(config.payments.razorpay.keyId && config.payments.razorpay.keySecret);

/**
 * One Razorpay API call → {ok, status, body}. Throws only when Razorpay cannot
 * be reached at all (the caller decides whether that is fatal).
 */
async function razorpayApi(method, path, body) {
  const { keyId, keySecret, apiBase } = config.payments.razorpay;
  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const json = await response.json().catch(() => null);
  return { ok: response.ok, status: response.status, body: json };
}

async function createRazorpayOrder(amountPaise, receipt, notes) {
  if (!razorpayReady()) throw new ApiError(503, 'payment_provider_error', 'Online payment is not configured yet');
  let res;
  try {
    res = await razorpayApi('POST', '/orders', { amount: amountPaise, currency: 'INR', receipt, notes });
  } catch (e) {
    console.error('[payments] razorpay unreachable:', e.message);
    throw new ApiError(503, 'payment_provider_error', 'Could not start the payment — try again in a minute');
  }
  if (!res.ok || !res.body?.id) {
    console.error('[payments] razorpay rejected the order:', res.status, JSON.stringify(res.body)?.slice(0, 200));
    throw new ApiError(503, 'payment_provider_error', 'Could not start the payment — try again in a minute');
  }
  return res.body.id;
}

function razorpaySignatureOk(orderId, paymentId, signature) {
  if (!orderId || !paymentId || !signature) return false;
  const expected = createHmac('sha256', config.payments.razorpay.keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(String(signature));
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * Accounts on manual capture would auto-refund an authorized payment after a
 * few days, so a confirmed payment that is still `authorized` is captured
 * here. Never throws: problems are logged (auto-capture accounts need nothing).
 */
async function ensureCaptured(paymentId, amountPaise) {
  try {
    const got = await razorpayApi('GET', `/payments/${encodeURIComponent(paymentId)}`);
    if (!got.ok) {
      console.error('[payments] could not fetch payment', paymentId, got.status);
      return;
    }
    if (got.body?.status !== 'authorized') return;
    const cap = await razorpayApi('POST', `/payments/${encodeURIComponent(paymentId)}/capture`, {
      amount: amountPaise,
      currency: 'INR',
    });
    if (!cap.ok) console.error('[payments] capture failed for', paymentId, cap.status, JSON.stringify(cap.body)?.slice(0, 200));
  } catch (e) {
    console.error('[payments] capture check failed for', paymentId, e.message);
  }
}

/** The captured (else authorized) payment id of a Razorpay order Razorpay reports paid, or null. */
async function paidRazorpayPaymentId(orderId) {
  const order = await razorpayApi('GET', `/orders/${encodeURIComponent(orderId)}`);
  if (!order.ok || order.body?.status !== 'paid') return null;
  const pays = await razorpayApi('GET', `/orders/${encodeURIComponent(orderId)}/payments`);
  const items = Array.isArray(pays.body?.items) ? pays.body.items : [];
  const hit = items.find((p) => p.status === 'captured') || items.find((p) => p.status === 'authorized');
  return hit?.id ?? 'unknown';
}

// ---- settling ----------------------------------------------------------------

/**
 * Marks a locked payments row as paid inside `client`'s transaction: stamps
 * profiles.paid_at and — when the customer is already active — puts the hidden
 * profile live. A profile that is gone or already paid makes the row
 * 'refund_due' instead (the money came in, but must go back). Idempotent for
 * rows that are already settled. Returns the updated row.
 */
async function settle(client, payment, providerPaymentId) {
  if (payment.status === 'paid' || payment.status === 'refund_due') return payment;
  const paymentId = providerPaymentId ?? payment.provider_payment_id ?? null;

  const prof = await client.query('SELECT id, paid_at FROM profiles WHERE id = $1 FOR UPDATE', [payment.profile_id]);
  const profile = prof.rows[0];
  if (!profile || profile.paid_at) {
    // No real money moved for mock checkouts: refuse (the transaction rolls back).
    if (payment.provider === 'mock') {
      if (!profile) throw notFound('profile_not_found', 'This profile no longer exists');
      throw conflict('already_paid', 'This profile is already paid for');
    }
    const note = profile
      ? 'Profile was already paid by another payment — refund this one'
      : 'Profile was deleted before this payment completed — refund it';
    console.warn(`[payments] payment ${payment.id} (${payment.provider_order_id}) is refund_due: ${note}`);
    const { rows } = await client.query(
      `UPDATE payments SET status = 'refund_due', provider_payment_id = $2, paid_at = now(),
              note = COALESCE(note || ' · ', '') || $3
        WHERE id = $1 RETURNING *`,
      [payment.id, paymentId, note],
    );
    return rows[0];
  }

  const { rows } = await client.query(
    `UPDATE payments SET status = 'paid', provider_payment_id = $2, paid_at = now() WHERE id = $1 RETURNING *`,
    [payment.id, paymentId],
  );
  // Live now only if the agent has already approved the customer; otherwise
  // approval flips it (transitionCustomer).
  await client.query(
    `UPDATE profiles p
        SET paid_at = now(), updated_at = now(),
            status = CASE WHEN p.status = 'hidden' AND cu.status = 'active' THEN 'active' ELSE p.status END
       FROM customers cu
      WHERE p.id = $1 AND cu.id = p.customer_id`,
    [payment.profile_id],
  );
  await refreshUploaderApproval(client, payment.profile_id);
  return rows[0];
}

/** Settles the razorpay payment row for `orderId` (if we know it). Returns the row or null. */
async function settleRazorpayOrder(orderId, providerPaymentId) {
  return tx(async (client) => {
    const { rows } = await client.query(
      `SELECT * FROM payments WHERE provider = 'razorpay' AND provider_order_id = $1 FOR UPDATE`,
      [orderId],
    );
    if (!rows[0]) return null;
    return settle(client, rows[0], providerPaymentId);
  });
}

/**
 * Safety net (§9.19 B): asks Razorpay about this profile's recent open orders
 * and settles any it reports paid — e.g. the app died between paying and
 * confirming. Returns true when one of them paid the profile. Razorpay being
 * unreachable is logged and ignored here.
 */
async function syncOpenRazorpayOrders(profileId) {
  if (!razorpayReady()) return false;
  const open = await many(
    `SELECT id, provider_order_id FROM payments
      WHERE profile_id = $1 AND provider = 'razorpay' AND status IN ('created','failed')
        AND created_at > now() - interval '7 days'
      ORDER BY id DESC LIMIT 5`,
    [profileId],
  );
  let paid = false;
  for (const row of open) {
    try {
      const paymentId = await paidRazorpayPaymentId(row.provider_order_id);
      if (!paymentId) continue;
      const settled = await settleRazorpayOrder(row.provider_order_id, paymentId === 'unknown' ? null : paymentId);
      if (settled?.status === 'paid') paid = true;
    } catch (e) {
      console.error('[payments] could not check order', row.provider_order_id, e.message);
    }
  }
  return paid;
}

// ---- the customer's checkout -------------------------------------------------

/**
 * Starts a checkout for one of the customer's profiles: 409 already_paid,
 * 404 when it is not theirs. Returns the new payments row.
 */
export async function createProfilePayment(customer, profileId) {
  const profile = await one('SELECT id, customer_id, paid_at FROM profiles WHERE id = $1', [profileId]);
  if (!profile || profile.customer_id !== customer.id) throw notFound('profile_not_found', 'Profile not found');
  if (profile.paid_at) throw conflict('already_paid', 'This profile is already paid for');
  if (await syncOpenRazorpayOrders(profileId)) throw conflict('already_paid', 'This profile is already paid for');

  const provider = config.payments.provider;
  const amount = feePaise();

  if (provider === 'upi') {
    if (!upiReady()) throw upiNotReady();
    // One open UPI payment per profile: reuse it (a rejected one can be corrected).
    const open = await one(
      `SELECT * FROM payments WHERE profile_id = $1 AND provider = 'upi' AND purpose = 'profile_registration'
          AND status IN ('created','submitted','failed') ORDER BY id DESC LIMIT 1`,
      [profileId],
    );
    if (open?.status === 'submitted') {
      throw conflict('payment_under_review', 'Your payment is being verified — we will confirm it shortly');
    }
    if (open) return open;
    return one(
      `INSERT INTO payments (customer_id, profile_id, amount_paise, currency, provider)
       VALUES ($1, $2, $3, 'INR', 'upi') RETURNING *`,
      [customer.id, profileId, amount],
    );
  }

  const receipt = `gp${profileId}-${Date.now().toString(36)}`;
  const orderId =
    provider === 'razorpay'
      ? await createRazorpayOrder(amount, receipt, { profile_id: String(profileId), customer_id: String(customer.id) })
      : `mock_${randomBytes(8).toString('hex')}`;

  return one(
    `INSERT INTO payments (customer_id, profile_id, amount_paise, currency, provider, provider_order_id)
     VALUES ($1, $2, $3, 'INR', $4, $5) RETURNING *`,
    [customer.id, profileId, amount, provider, orderId],
  );
}

/**
 * Completes a checkout (SPEC §9.12 / §9.19 B): verifies with the provider and
 * settles the payment. A mock 'failure' outcome records a failed attempt and
 * returns that row (status 'failed'); the app starts a new order to retry.
 * A razorpay payment is then captured if it is only authorized.
 * Returns the payments row; 409 already_paid when another payment had
 * already paid the profile (this one is then 'refund_due').
 */
export async function confirmPayment(customer, paymentId, { provider_payment_id, signature, outcome } = {}) {
  if (!Number.isInteger(paymentId) || paymentId <= 0) throw notFound('payment_not_found', 'Payment not found');

  const result = await tx(async (client) => {
    const { rows } = await client.query('SELECT * FROM payments WHERE id = $1 AND customer_id = $2 FOR UPDATE', [
      paymentId,
      customer.id,
    ]);
    const payment = rows[0];
    if (!payment) throw notFound('payment_not_found', 'Payment not found');
    if (payment.provider === 'upi') {
      throw badRequest('wrong_provider', 'UPI payments are confirmed by an admin after you submit the UPI reference');
    }
    if (payment.status === 'paid' || payment.status === 'refund_due') return payment; // idempotent retry
    // A razorpay order marked failed can still be paid later (slow UPI).
    const confirmable = payment.status === 'created' || (payment.status === 'failed' && payment.provider === 'razorpay');
    if (!confirmable) throw conflict('wrong_status', `This payment is already ${payment.status}`);

    let ok;
    let providerPaymentId = provider_payment_id ?? null;
    if (payment.provider === 'mock') {
      ok = outcome !== 'failure';
      providerPaymentId = providerPaymentId ?? `mockpay_${randomBytes(6).toString('hex')}`;
    } else {
      ok = razorpaySignatureOk(payment.provider_order_id, providerPaymentId, signature);
      if (!ok && outcome !== 'failure') {
        throw badRequest('payment_verification_failed', 'We could not verify this payment — contact your agent');
      }
    }

    if (!ok) {
      const { rows: failed } = await client.query(
        `UPDATE payments SET status = 'failed', provider_payment_id = COALESCE($2, provider_payment_id)
          WHERE id = $1 RETURNING *`,
        [payment.id, providerPaymentId],
      );
      return failed[0];
    }
    return settle(client, payment, providerPaymentId);
  });

  if (result.provider === 'razorpay' && result.provider_payment_id && result.status !== 'failed') {
    await ensureCaptured(result.provider_payment_id, result.amount_paise);
  }
  if (result.status === 'refund_due') throw conflict('already_paid', 'This profile is already paid for');
  return result;
}

// ---- Razorpay webhook ----------------------------------------------------------

/**
 * POST /api/payments/razorpay/webhook (§9.19 B). `rawBody` is the exact bytes
 * Razorpay signed. order.paid / payment.captured settle the matching payment;
 * anything else correctly signed is acknowledged and ignored.
 */
export async function handleRazorpayWebhook(rawBody, signatureHeader) {
  const secret = config.payments.razorpay.webhookSecret;
  if (!secret) throw new ApiError(503, 'webhook_not_configured', 'Webhook secret is not set');

  const expected = createHmac('sha256', secret).update(rawBody).digest('hex');
  const given = Buffer.from(String(signatureHeader || ''));
  if (given.length !== expected.length || !timingSafeEqual(Buffer.from(expected), given)) {
    throw badRequest('invalid_signature', 'Invalid signature');
  }

  let event;
  try {
    event = JSON.parse(rawBody.toString('utf8'));
  } catch {
    throw badRequest('invalid_body', 'Invalid JSON');
  }
  if (event?.event !== 'order.paid' && event?.event !== 'payment.captured') return { ok: true, ignored: true };

  const pay = event.payload?.payment?.entity;
  const orderId = event.payload?.order?.entity?.id ?? pay?.order_id;
  if (!orderId) return { ok: true, ignored: true };
  const settled = await settleRazorpayOrder(orderId, pay?.id ?? null);
  return { ok: true, ...(settled ? { status: settled.status } : { ignored: true }) };
}

/**
 * Records a registration fee paid to the agent in cash (SPEC §9.13): a 'cash'
 * payment by `agentId`, profiles.paid_at, and the profile goes live when its
 * customer is active. 409 already_paid.
 */
export async function recordCashPayment({ profileId, customerId, agentId, note = null }) {
  return tx(async (client) => {
    const { rows } = await client.query(
      'SELECT id, paid_at FROM profiles WHERE id = $1 AND customer_id = $2 FOR UPDATE',
      [profileId, customerId],
    );
    if (!rows[0]) throw notFound('profile_not_found', 'Profile not found');
    if (rows[0].paid_at) throw conflict('already_paid', 'This profile is already paid for');
    const { rows: paid } = await client.query(
      `INSERT INTO payments (customer_id, profile_id, amount_paise, currency, provider, status, paid_at, recorded_by, note)
       VALUES ($1, $2, $3, 'INR', 'cash', 'paid', now(), $4, $5) RETURNING *`,
      [customerId, profileId, feePaise(), agentId, note],
    );
    await client.query(
      `UPDATE profiles p
          SET paid_at = now(), updated_at = now(),
              status = CASE WHEN p.status = 'hidden' AND cu.status = 'active' THEN 'active' ELSE p.status END
         FROM customers cu
        WHERE p.id = $1 AND cu.id = p.customer_id`,
      [profileId],
    );
    await refreshUploaderApproval(client, profileId);
    return paid[0];
  });
}

// ---- direct UPI: submit the UTR, admin verification (SPEC §9.20) ------------------

/**
 * The payer (a customer for a profile fee, an agent for a community fee) hands
 * in the 12-digit UPI reference. Allowed from created / failed (a rejected
 * claim may be corrected). 404 when it is not theirs, 409 wrong_status,
 * 409 utr_already_used, 409 already_paid (profile paid meanwhile).
 */
export async function submitUpiPayment(paymentId, { customerId = null, agentId = null }, utr) {
  if (!Number.isInteger(paymentId) || paymentId <= 0) throw notFound('payment_not_found', 'Payment not found');
  return tx(async (client) => {
    const { rows } = await client.query('SELECT * FROM payments WHERE id = $1 FOR UPDATE', [paymentId]);
    const p = rows[0];
    const mine =
      p &&
      (customerId
        ? p.customer_id === customerId && p.purpose === 'profile_registration'
        : agentId && p.agent_id === agentId && p.purpose === 'extra_community');
    if (!mine) throw notFound('payment_not_found', 'Payment not found');
    if (p.provider !== 'upi') throw badRequest('wrong_provider', 'This is not a UPI payment');
    if (!['created', 'failed'].includes(p.status)) throw conflict('wrong_status', `This payment is already ${p.status}`);
    if (p.purpose === 'profile_registration') {
      const prof = await client.query('SELECT paid_at FROM profiles WHERE id = $1', [p.profile_id]);
      if (prof.rows[0]?.paid_at) throw conflict('already_paid', 'This profile is already paid for');
    }
    const dup = await client.query(
      `SELECT 1 FROM payments WHERE utr = $1 AND id <> $2 AND status IN ('submitted','paid')`,
      [utr, p.id],
    );
    if (dup.rows[0]) throw conflict('utr_already_used', 'This UPI reference was already used for another payment');
    const { rows: up } = await client.query(
      `UPDATE payments SET status = 'submitted', utr = $2, submitted_at = now(),
              reject_reason = NULL, verified_by = NULL, verified_at = NULL
        WHERE id = $1 RETURNING *`,
      [p.id, utr],
    );
    return up[0];
  });
}

/** Approves a community request inside `client`'s transaction; adds the community. */
async function approveCommunityRequest(client, requestId, adminId) {
  if (!requestId) return;
  const { rows } = await client.query(
    `UPDATE community_change_requests SET status = 'approved', decided_by = $2, decided_at = now()
      WHERE id = $1 AND status = 'pending' RETURNING agent_id, community_id`,
    [requestId, adminId],
  );
  if (rows[0]) {
    await client.query(
      'INSERT INTO agent_communities (agent_id, community_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [rows[0].agent_id, rows[0].community_id],
    );
  }
}

/**
 * Admin confirms a submitted UPI payment after checking the UTR and amount in
 * the bank: a profile fee is settled like any payment (paid, profile paid,
 * live when the customer is active); a community fee becomes paid and its
 * request approved. 409 wrong_status unless submitted.
 */
export async function approveUpiPayment(paymentId, adminId) {
  if (!Number.isInteger(paymentId) || paymentId <= 0) throw notFound('payment_not_found', 'Payment not found');
  return tx(async (client) => {
    const { rows } = await client.query('SELECT * FROM payments WHERE id = $1 FOR UPDATE', [paymentId]);
    const p = rows[0];
    if (!p) throw notFound('payment_not_found', 'Payment not found');
    if (p.provider !== 'upi') throw badRequest('wrong_provider', 'This is not a UPI payment');
    if (p.status !== 'submitted') throw conflict('wrong_status', `This payment is ${p.status}, not waiting for verification`);
    await client.query('UPDATE payments SET verified_by = $2, verified_at = now() WHERE id = $1', [p.id, adminId]);
    if (p.purpose === 'extra_community') {
      const { rows: paid } = await client.query(
        `UPDATE payments SET status = 'paid', paid_at = now(), provider_payment_id = utr WHERE id = $1 RETURNING *`,
        [p.id],
      );
      await approveCommunityRequest(client, p.community_request_id, adminId);
      return paid[0];
    }
    return settle(client, { ...p, verified_by: adminId }, p.utr);
  });
}

/** Admin rejects a submitted UPI payment (money not found): failed + reason; the payer may resubmit. */
export async function rejectUpiPayment(paymentId, adminId, reason) {
  if (!Number.isInteger(paymentId) || paymentId <= 0) throw notFound('payment_not_found', 'Payment not found');
  return tx(async (client) => {
    const { rows } = await client.query('SELECT * FROM payments WHERE id = $1 FOR UPDATE', [paymentId]);
    const p = rows[0];
    if (!p) throw notFound('payment_not_found', 'Payment not found');
    if (p.provider !== 'upi') throw badRequest('wrong_provider', 'This is not a UPI payment');
    if (p.status !== 'submitted') throw conflict('wrong_status', `This payment is ${p.status}, not waiting for verification`);
    const { rows: up } = await client.query(
      `UPDATE payments SET status = 'failed', reject_reason = $3, verified_by = $2, verified_at = now()
        WHERE id = $1 RETURNING *`,
      [p.id, adminId, reason],
    );
    return up[0];
  });
}

/** Creates the UPI payment for a paid community request (inside the caller's transaction). */
export async function createCommunityFeePayment(client, agentId, requestId) {
  const { rows } = await client.query(
    `INSERT INTO payments (agent_id, community_request_id, purpose, amount_paise, currency, provider)
     VALUES ($1, $2, 'extra_community', $3, 'INR', 'upi') RETURNING *`,
    [agentId, requestId, communityFeePaise()],
  );
  return rows[0];
}

/**
 * Admin decides a community request that carries a fee (SPEC §9.20 C) inside
 * `client`'s transaction: approve needs the payment submitted (it is verified
 * now) or paid — 409 payment_not_submitted otherwise; reject turns a submitted
 * payment into refund_due and an unsubmitted one into failed.
 */
export async function settleCommunityFeeDecision(client, request, decision, adminId) {
  const { rows } = await client.query(
    `SELECT * FROM payments WHERE community_request_id = $1 AND purpose = 'extra_community'
      ORDER BY id DESC LIMIT 1 FOR UPDATE`,
    [request.id],
  );
  const p = rows[0];
  if (decision === 'approved') {
    if (!p || (p.status !== 'submitted' && p.status !== 'paid')) {
      throw conflict('payment_not_submitted', 'The agent has not submitted the ₹ payment for this community yet');
    }
    if (p.status === 'submitted') {
      await client.query(
        `UPDATE payments SET status = 'paid', paid_at = now(), provider_payment_id = utr,
                verified_by = $2, verified_at = now() WHERE id = $1`,
        [p.id, adminId],
      );
    }
    return;
  }
  if (!p) return;
  if (p.status === 'submitted') {
    await client.query(
      `UPDATE payments SET status = 'refund_due', verified_by = $2, verified_at = now(),
              note = COALESCE(note || ' · ', '') || 'Community request rejected — refund it'
        WHERE id = $1`,
      [p.id, adminId],
    );
  } else if (p.status === 'created' || p.status === 'failed') {
    await client.query(
      `UPDATE payments SET status = 'failed', reject_reason = COALESCE(reject_reason, 'Community request rejected')
        WHERE id = $1`,
      [p.id],
    );
  }
}

/** Admin list of UPI payments (SPEC §9.20 D). */
export async function listUpiPayments(status) {
  const where = status === 'all' ? "p.provider = 'upi'" : "p.provider = 'upi' AND p.status = $1";
  const rows = await many(
    `SELECT p.*, cu.full_name AS cu_name, cu.phone AS cu_phone,
            pr.full_name AS pr_name, pr.profile_code AS pr_code,
            a.full_name AS ag_name, a.phone AS ag_phone, a.agent_code AS ag_code,
            c.id AS cm_id, c.name AS cm_name
       FROM payments p
       LEFT JOIN customers cu ON cu.id = p.customer_id
       LEFT JOIN profiles pr ON pr.id = p.profile_id
       LEFT JOIN agents a ON a.id = p.agent_id
       LEFT JOIN community_change_requests ccr ON ccr.id = p.community_request_id
       LEFT JOIN communities c ON c.id = ccr.community_id
      WHERE ${where}
      ORDER BY COALESCE(p.submitted_at, p.created_at) DESC, p.id DESC
      LIMIT 200`,
    status === 'all' ? [] : [status],
  );
  return rows.map((r) => ({
    id: r.id,
    purpose: r.purpose,
    status: r.status,
    amount_inr: r.amount_paise / 100,
    utr: r.utr ?? null,
    reference: `WB${r.id}`,
    submitted_at: r.submitted_at ?? null,
    verified_at: r.verified_at ?? null,
    reject_reason: r.reject_reason ?? null,
    customer: r.customer_id ? { id: r.customer_id, full_name: r.cu_name, phone: r.cu_phone } : null,
    profile: r.profile_id ? { id: r.profile_id, full_name: r.pr_name, profile_code: r.pr_code ?? null } : null,
    agent: r.agent_id ? { id: r.agent_id, full_name: r.ag_name, phone: r.ag_phone, agent_code: r.ag_code ?? null } : null,
    community: r.cm_id ? { id: r.cm_id, name: r.cm_name } : null,
  }));
}
