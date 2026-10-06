// The Gandharva registration fee — SPEC §9.12. One payment per customer
// profile; a profile is visible to others only when it is paid AND its
// customer is active.
//
// Provider is chosen by env (see .env.example), no code change to switch:
//   PAYMENT_PROVIDER=mock      (default) nothing is charged; confirm succeeds
//                              unless the app asks for outcome 'failure'.
//   PAYMENT_PROVIDER=razorpay  RAZORPAY_KEY_ID + RAZORPAY_KEY_SECRET; orders are
//                              created through Razorpay's Orders API and confirm
//                              checks the Checkout signature
//                              (HMAC-SHA256 of "order_id|payment_id").
// The razorpay path is written to Razorpay's documented API but has not been
// exercised against a live account yet — the app also needs the Razorpay
// Checkout plugin before it can be switched on.
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { one, tx } from './db.js';
import { ApiError, badRequest, conflict, notFound } from './errors.js';

const RAZORPAY_ORDERS_URL = 'https://api.razorpay.com/v1/orders';

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

async function createRazorpayOrder(amountPaise, receipt) {
  const { keyId, keySecret } = config.payments.razorpay;
  if (!keyId || !keySecret) throw new ApiError(503, 'payment_provider_error', 'Online payment is not configured yet');
  let response;
  try {
    response = await fetch(RAZORPAY_ORDERS_URL, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString('base64')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ amount: amountPaise, currency: 'INR', receipt }),
    });
  } catch (e) {
    console.error('[payments] razorpay unreachable:', e.message);
    throw new ApiError(503, 'payment_provider_error', 'Could not start the payment — try again in a minute');
  }
  const body = await response.json().catch(() => null);
  if (!response.ok || !body?.id) {
    console.error('[payments] razorpay rejected the order:', response.status, JSON.stringify(body)?.slice(0, 200));
    throw new ApiError(503, 'payment_provider_error', 'Could not start the payment — try again in a minute');
  }
  return body.id;
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
 * Starts a checkout for one of the customer's profiles: 409 already_paid,
 * 404 when it is not theirs. Returns the new payments row.
 */
export async function createProfilePayment(customer, profileId) {
  const profile = await one('SELECT id, customer_id, paid_at FROM profiles WHERE id = $1', [profileId]);
  if (!profile || profile.customer_id !== customer.id) throw notFound('profile_not_found', 'Profile not found');
  if (profile.paid_at) throw conflict('already_paid', 'This profile is already paid for');

  const provider = config.payments.provider;
  const amount = feePaise();
  const receipt = `gp${profileId}-${Date.now().toString(36)}`;
  const orderId =
    provider === 'razorpay' ? await createRazorpayOrder(amount, receipt) : `mock_${randomBytes(8).toString('hex')}`;

  return one(
    `INSERT INTO payments (customer_id, profile_id, amount_paise, currency, provider, provider_order_id)
     VALUES ($1, $2, $3, 'INR', $4, $5) RETURNING *`,
    [customer.id, profileId, amount, provider, orderId],
  );
}

const confirmable = (status) => status === 'created';

/**
 * Completes a checkout (SPEC §9.12): verifies with the provider, marks the
 * payment paid, stamps profiles.paid_at and — when the customer is already
 * active — puts the hidden profile live. A 'failure' outcome records a failed
 * attempt and returns that row (status 'failed'); the app starts a new order
 * to retry. Returns the payments row.
 */
export async function confirmPayment(customer, paymentId, { provider_payment_id, signature, outcome } = {}) {
  if (!Number.isInteger(paymentId) || paymentId <= 0) throw notFound('payment_not_found', 'Payment not found');

  return tx(async (client) => {
    const { rows } = await client.query('SELECT * FROM payments WHERE id = $1 AND customer_id = $2 FOR UPDATE', [
      paymentId,
      customer.id,
    ]);
    const payment = rows[0];
    if (!payment) throw notFound('payment_not_found', 'Payment not found');
    if (payment.status === 'paid') return payment; // idempotent retry from the app
    if (!confirmable(payment.status)) throw conflict('wrong_status', `This payment is already ${payment.status}`);

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
      await client.query(`UPDATE payments SET status = 'failed', provider_payment_id = $2 WHERE id = $1`, [
        payment.id,
        providerPaymentId,
      ]);
      return { ...payment, status: 'failed', provider_payment_id: providerPaymentId };
    }

    const prof = await client.query('SELECT id, paid_at FROM profiles WHERE id = $1 FOR UPDATE', [payment.profile_id]);
    if (!prof.rows[0]) throw notFound('profile_not_found', 'This profile no longer exists');
    if (prof.rows[0].paid_at) throw conflict('already_paid', 'This profile is already paid for');

    const { rows: paid } = await client.query(
      `UPDATE payments SET status = 'paid', provider_payment_id = $2, paid_at = now() WHERE id = $1 RETURNING *`,
      [payment.id, providerPaymentId],
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
    return paid[0];
  });
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
