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
//
// Every route that learns "this order is paid" (confirm, the safety net in
// createProfilePayment, the webhook) goes through settle(), so a payment is
// counted once and a profile is never paid twice (a second payment becomes
// 'refund_due' — refund it from the Razorpay dashboard).
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { many, one, tx } from './db.js';
import { ApiError, badRequest, conflict, notFound } from './errors.js';

export const feePaise = () => Math.round(config.payments.profileFeeInr * 100);

/** Wire shape of a payments row (never the provider secret). */
export function paymentPublic(row) {
  if (!row) return null;
  return {
    id: row.id,
    profile_id: row.profile_id,
    status: row.status,
    amount_paise: row.amount_paise,
    amount_inr: row.amount_paise / 100,
    currency: row.currency,
    provider: row.provider,
    order_id: row.provider_order_id,
    // Razorpay Checkout needs the public key id; mock has none.
    key_id: row.provider === 'razorpay' ? config.payments.razorpay.keyId : null,
    created_at: row.created_at,
    paid_at: row.paid_at ?? null,
  };
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
    if (payment.provider !== 'razorpay') {
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
    return paid[0];
  });
}
