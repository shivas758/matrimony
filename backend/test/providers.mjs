/**
 * Provider test for SPEC §9.19 — Firebase phone-auth OTP, Razorpay checkout and
 * the Fast2SMS OTP adapter (a second API on PORT+1 with OTP_PROVIDER=fast2sms) and
 * the StartMessaging adapter (a third API on PORT+2 with OTP_PROVIDER=startmessaging).
 *
 *   DATABASE_URL=postgres://matrimony@127.0.0.1:5434/matrimony node test/providers.mjs
 *
 * Self-contained: it starts two in-process fakes — Google's securetoken
 * certificate endpoint (with a throw-away RSA certificate made by `openssl`)
 * and Razorpay's REST API — then spawns its own API (PORT, default 3101) with
 * OTP_PROVIDER=firebase and PAYMENT_PROVIDER=razorpay pointed at them through
 * the FIREBASE_CERTS_URL / RAZORPAY_API_BASE test hooks. The database must
 * already have schema.sql + migrations loaded (the seeded admin is used).
 * Never point it at production. Needs `openssl` on PATH.
 */
import { execFileSync, spawn } from 'node:child_process';
import { createHmac, generateKeyPairSync, randomBytes } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import jwt from 'jsonwebtoken';

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('Set DATABASE_URL to a test database (schema + migrations loaded).');
  process.exit(2);
}
const PORT = Number(process.env.PORT || 3101);
const BASE = `http://127.0.0.1:${PORT}`;
const ADMIN_PHONE = process.env.ADMIN_PHONE || '9999999999';
const ADMIN_PASS = process.env.ADMIN_PASS || 'ChangeMe@123';

const PROJECT = 'wedbook-test';
const KID = 'test-kid-1';
const RZP_KEY = 'rzp_test_fake';
const RZP_SECRET = 'fake_key_secret';
const WEBHOOK_SECRET = 'fake_webhook_secret';
const BACKEND = join(dirname(fileURLToPath(import.meta.url)), '..');

let pass = 0;
const failures = [];
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;
function check(label, expected, actual) {
  if (JSON.stringify(expected) === JSON.stringify(actual)) {
    pass++;
    console.log(`  ${green('PASS')} ${label}`);
  } else {
    failures.push(label);
    console.log(`  ${red('FAIL')} ${label}\n       expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
const assertTrue = (label, cond) => check(label, true, Boolean(cond));
const step = (t) => console.log(`\n${bold(t)}`);

// ---- keys ------------------------------------------------------------------
const tmp = mkdtempSync(join(tmpdir(), 'wedbook-providers-'));
execFileSync('openssl', [
  'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=securetoken',
  '-keyout', join(tmp, 'key.pem'), '-out', join(tmp, 'cert.pem'),
], { stdio: 'ignore' });
const PRIVATE_KEY = readFileSync(join(tmp, 'key.pem'), 'utf8');
const CERT = readFileSync(join(tmp, 'cert.pem'), 'utf8');
const IMPOSTOR_KEY = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs8', format: 'pem' });

/** A Firebase-style ID token for `phone` (10 digits); `over` patches claims, `opts` the signing. */
function idToken(phone, over = {}, { key = PRIVATE_KEY, kid = KID, algorithm = 'RS256' } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    auth_time: now - 5,
    user_id: `uid${phone}`,
    sub: `uid${phone}`,
    iat: now - 5,
    exp: now + 3595,
    phone_number: `+91${phone}`,
    firebase: { identities: { phone: [`+91${phone}`] }, sign_in_provider: 'phone' },
    ...over,
  };
  for (const k of Object.keys(claims)) if (claims[k] === undefined) delete claims[k];
  return jwt.sign(claims, key, { algorithm, keyid: kid, noTimestamp: true });
}

// ---- fake Google certificate endpoint ---------------------------------------
let certsDown = false;
let certFetches = 0;
const certServer = http.createServer((req, res) => {
  certFetches++;
  if (certsDown) {
    res.writeHead(500);
    return res.end('down');
  }
  res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=60' });
  res.end(JSON.stringify({ [KID]: CERT }));
});

// ---- fake Razorpay -------------------------------------------------------------
const rzp = { orders: new Map(), payments: new Map(), calls: [] };
let orderSeq = 0;
const rzpServer = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const json = body ? JSON.parse(body) : null;
    const authOk = req.headers.authorization === `Basic ${Buffer.from(`${RZP_KEY}:${RZP_SECRET}`).toString('base64')}`;
    rzp.calls.push({ method: req.method, url: req.url, body: json, authOk });
    const send = (status, obj) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(obj));
    };
    if (!authOk) return send(401, { error: { code: 'BAD_REQUEST_ERROR', description: 'Authentication failed' } });
    let m;
    if (req.method === 'POST' && req.url === '/v1/orders') {
      const id = `order_T${++orderSeq}${randomBytes(3).toString('hex')}`;
      const order = { id, entity: 'order', amount: json.amount, currency: json.currency, receipt: json.receipt, notes: json.notes, status: 'created', payments: [] };
      rzp.orders.set(id, order);
      return send(200, order);
    }
    if (req.method === 'GET' && (m = /^\/v1\/orders\/([^/]+)\/payments$/.exec(req.url))) {
      const o = rzp.orders.get(m[1]);
      return o ? send(200, { entity: 'collection', count: o.payments.length, items: o.payments }) : send(404, {});
    }
    if (req.method === 'GET' && (m = /^\/v1\/orders\/([^/]+)$/.exec(req.url))) {
      const o = rzp.orders.get(m[1]);
      return o ? send(200, { id: o.id, status: o.status, amount: o.amount }) : send(404, {});
    }
    if (req.method === 'GET' && (m = /^\/v1\/payments\/([^/]+)$/.exec(req.url))) {
      return send(200, { id: m[1], status: rzp.payments.get(m[1]) ?? 'authorized' });
    }
    if (req.method === 'POST' && (m = /^\/v1\/payments\/([^/]+)\/capture$/.exec(req.url))) {
      rzp.payments.set(m[1], 'captured');
      return send(200, { id: m[1], status: 'captured', amount: json?.amount });
    }
    send(404, { error: 'not faked' });
  });
});
/** Razorpay marks `orderId` paid by a captured `paymentId` (what a completed checkout does). */
function rzpPay(orderId, paymentId) {
  const o = rzp.orders.get(orderId);
  o.status = 'paid';
  o.payments.push({ id: paymentId, order_id: orderId, status: 'captured', amount: o.amount });
  rzp.payments.set(paymentId, 'captured');
}
// ---- fake Fast2SMS (bulkV2) -------------------------------------------------------
const f2s = { calls: [], fail: false };
const f2sServer = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    f2s.calls.push({ method: req.method, url: req.url, auth: req.headers.authorization, body: body ? JSON.parse(body) : null });
    res.writeHead(f2s.fail ? 400 : 200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(f2s.fail
      ? { return: false, status_code: 416, message: "You don't have sufficient wallet balance" }
      : { return: true, request_id: 'f2s-req-1', message: ['SMS sent successfully.'] }));
  });
});

// ---- fake StartMessaging (/otp/send) ------------------------------------------------
const sm = { calls: [], fail: false };
const smServer = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    sm.calls.push({ method: req.method, url: req.url, key: req.headers['x-api-key'], body: body ? JSON.parse(body) : null });
    res.writeHead(sm.fail ? 402 : 201, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(sm.fail
      ? { success: false, statusCode: 402, message: 'Insufficient wallet balance' }
      : { success: true, statusCode: 201, requestId: 'req_abc123', data: { otpRequestId: 'u1', messageId: 'm1', status: 'queued' } }));
  });
});

const checkoutSignature = (orderId, paymentId) => createHmac('sha256', RZP_SECRET).update(`${orderId}|${paymentId}`).digest('hex');

// ---- HTTP helpers ----------------------------------------------------------------
let ipSeq = 1;
const nextIp = () => `10.77.${Math.floor(ipSeq / 250)}.${(ipSeq++ % 250) + 1}`;
const api = (method, path, token, body) => apiAt(BASE, method, path, token, body);
async function apiAt(base, method, path, token, body) {
  const headers = { 'X-Forwarded-For': nextIp() };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(`${base}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let parsed = text;
  try {
    parsed = JSON.parse(text);
  } catch {
    /* text */
  }
  return { status: res.status, body: parsed };
}
async function apiForm(path, token, fields) {
  const form = new FormData();
  for (const [k, v] of Object.entries(fields)) form.append(k, String(v));
  const res = await fetch(`${BASE}${path}`, { method: 'POST', headers: { 'X-Forwarded-For': nextIp(), Authorization: `Bearer ${token}` }, body: form });
  return { status: res.status, body: await res.json().catch(() => null) };
}
async function webhook(event, opts = {}) {
  const raw = JSON.stringify(event);
  // `signature: null` sends no header at all.
  const sig = 'signature' in opts ? opts.signature : createHmac('sha256', opts.secret ?? WEBHOOK_SECRET).update(raw).digest('hex');
  const res = await fetch(`${BASE}/api/payments/razorpay/webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(sig === null ? {} : { 'X-Razorpay-Signature': sig }) },
    body: raw,
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}
const orderPaidEvent = (orderId, paymentId) => ({
  entity: 'event',
  event: 'order.paid',
  payload: {
    payment: { entity: { id: paymentId, order_id: orderId, status: 'captured', amount: 15000 } },
    order: { entity: { id: orderId, status: 'paid', amount_paid: 15000 } },
  },
});
const randomPhone = () => `9${String(Math.floor(Math.random() * 1e9)).padStart(9, '0')}`;

// ---- run ---------------------------------------------------------------------------
await new Promise((r) => certServer.listen(0, '127.0.0.1', r));
await new Promise((r) => rzpServer.listen(0, '127.0.0.1', r));
await new Promise((r) => f2sServer.listen(0, '127.0.0.1', r));
await new Promise((r) => smServer.listen(0, '127.0.0.1', r));
const REVIEW_PHONE = `6${String(Math.floor(Math.random() * 1e9)).padStart(9, '0')}`;
const REVIEW_CODE = '246810';
// The Fast2SMS instance has its own reviewer number (one shared DB → separate cooldowns).
const REVIEW_PHONE2 = `6${String(Math.floor(Math.random() * 1e9)).padStart(9, '0')}`;
const baseEnv = (port) => ({
  PATH: process.env.PATH,
  SystemRoot: process.env.SystemRoot,
  DATABASE_URL,
  JWT_SECRET: 'providers-test-secret-0123456789',
  PORT: String(port),
  PUBLIC_BASE_URL: `http://127.0.0.1:${port}`,
  UPLOADS_DIR: join(tmp, 'uploads'),
  PUSH_PROVIDER: 'off',
  OTP_REVIEW_PHONE: REVIEW_PHONE,
  OTP_REVIEW_CODE: REVIEW_CODE,
  SITE_BUSINESS_NAME: 'Test Bureau Pvt Ltd',
  SITE_PHONE: '9036384100',
  SITE_EMAIL: 'help@example.com',
});
const api$ = spawn(process.execPath, ['src/server.js'], {
  cwd: BACKEND,
  env: {
    ...baseEnv(PORT),
    OTP_PROVIDER: 'firebase',
    FIREBASE_PROJECT_ID: PROJECT,
    FIREBASE_API_KEY: 'AIza-test-key',
    FIREBASE_SENDER_ID: '123456789',
    FIREBASE_APP_ID_AGENT: '1:123456789:android:agent',
    FIREBASE_APP_ID_CUSTOMER: '1:123456789:android:customer',
    FIREBASE_CERTS_URL: `http://127.0.0.1:${certServer.address().port}/certs`,
    PAYMENT_PROVIDER: 'razorpay',
    RAZORPAY_KEY_ID: RZP_KEY,
    RAZORPAY_KEY_SECRET: RZP_SECRET,
    RAZORPAY_WEBHOOK_SECRET: WEBHOOK_SECRET,
    RAZORPAY_API_BASE: `http://127.0.0.1:${rzpServer.address().port}/v1`,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let apiLog = '';
api$.stdout.on('data', (d) => (apiLog += d));
api$.stderr.on('data', (d) => (apiLog += d));
// The Fast2SMS instance (section 7).
const F2S_BASE = `http://127.0.0.1:${PORT + 1}`;
const f2sApi$ = spawn(process.execPath, ['src/server.js'], {
  cwd: BACKEND,
  env: {
    ...baseEnv(PORT + 1),
    OTP_PROVIDER: 'fast2sms',
    OTP_REVIEW_PHONE: REVIEW_PHONE2,
    OTP_MOCK_ECHO: 'true', // must be ignored for a real provider
    FAST2SMS_API_KEY: 'f2s_fake_key',
    FAST2SMS_API_URL: `http://127.0.0.1:${f2sServer.address().port}/dev/bulkV2`,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});
f2sApi$.stdout.on('data', (d) => (apiLog += d));
f2sApi$.stderr.on('data', (d) => (apiLog += d));
// The StartMessaging instance (section 10).
const SM_BASE = `http://127.0.0.1:${PORT + 2}`;
const smApi$ = spawn(process.execPath, ['src/server.js'], {
  cwd: BACKEND,
  env: {
    ...baseEnv(PORT + 2),
    OTP_PROVIDER: 'startmessaging',
    OTP_REVIEW_PHONE: '',
    STARTMESSAGING_API_KEY: 'sm_live_fake',
    STARTMESSAGING_TEMPLATE_ID: 'tpl_otp_1',
    STARTMESSAGING_API_URL: `http://127.0.0.1:${smServer.address().port}/otp/send`,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});
smApi$.stdout.on('data', (d) => (apiLog += d));
smApi$.stderr.on('data', (d) => (apiLog += d));
const shutdown = () => {
  api$.kill();
  f2sApi$.kill();
  smApi$.kill();
  certServer.close();
  rzpServer.close();
  f2sServer.close();
  smServer.close();
};

try {
  for (const base of [BASE, F2S_BASE, SM_BASE]) {
    for (let i = 0; i < 40; i++) {
      const up = await fetch(`${base}/api/health`).then((r) => r.ok, () => false);
      if (up) break;
      await new Promise((r) => setTimeout(r, 250));
    }
  }
  assertTrue('API started with OTP provider firebase, payments razorpay', /OTP provider firebase, payments razorpay/.test(apiLog));

  // ======================================================================
  step('1. Firebase OTP — send');
  const cPhone = randomPhone();
  const old = await api('POST', '/api/customer/auth/otp/send', null, { phone: cPhone });
  check('an app without firebase support → 426', 426, old.status);
  check('… app_update_required', 'app_update_required', old.body?.error);
  const send = await api('POST', '/api/customer/auth/otp/send', null, { phone: cPhone, firebase: true });
  check('customer send 200', 200, send.status);
  check('… provider firebase', 'firebase', send.body?.provider);
  check('… nothing sent by the server', false, send.body?.sent);
  check('… no mock code', undefined, send.body?.mock_code);
  check('… customer app options', { api_key: 'AIza-test-key', app_id: '1:123456789:android:customer', messaging_sender_id: '123456789', project_id: PROJECT }, send.body?.firebase);
  const aPhone = randomPhone();
  const aSend = await api('POST', '/api/auth/otp/send', null, { phone: aPhone, firebase: true });
  check('agent send → the agent app id', '1:123456789:android:agent', aSend.body?.firebase?.app_id);
  check('agent route without the flag → 426', 426, (await api('POST', '/api/auth/otp/send', null, { phone: aPhone })).status);
  const withCode = await api('POST', '/api/customer/auth/otp/verify', null, { phone: cPhone, code: '123456' });
  check('a typed code while the provider is firebase → 400', 400, withCode.status);
  check('… otp_provider_mismatch', 'otp_provider_mismatch', withCode.body?.error);
  check('neither code nor token → validation_failed', 'validation_failed', (await api('POST', '/api/customer/auth/otp/verify', null, { phone: cPhone })).body?.error);

  // ======================================================================
  step('2. Firebase OTP — ID token checks');
  const v = await api('POST', '/api/customer/auth/otp/verify', null, { phone: cPhone, firebase_id_token: idToken(cPhone) });
  check('valid token for a new number → 200', 200, v.status);
  check('… new: true', true, v.body?.new);
  assertTrue('… with a verification token', typeof v.body?.verification_token === 'string');
  check('certificates fetched once', 1, certFetches);
  const signup = await api('POST', '/api/customer/auth/signup', null, { full_name: 'Firebase Customer', phone: cPhone, phone_verification_token: v.body?.verification_token });
  check('customer signup with it → 201', 201, signup.status);
  const login = await api('POST', '/api/customer/auth/otp/verify', null, { phone: `+91${cPhone}`, firebase_id_token: idToken(cPhone) });
  check('next login with a fresh token → token', true, typeof login.body?.token === 'string');
  check('… same customer', signup.body?.customer?.id, login.body?.customer?.id);
  check('certificates came from the cache', 1, certFetches);

  const bad = async (label, token, code = 'invalid_firebase_token', phone = cPhone) => {
    const r = await api('POST', '/api/customer/auth/otp/verify', null, { phone, firebase_id_token: token });
    check(label, [400, code], [r.status, r.body?.error]);
  };
  const now = Math.floor(Date.now() / 1000);
  await bad('token for another number → phone_mismatch', idToken(randomPhone()), 'phone_mismatch');
  await bad('expired token', idToken(cPhone, { iat: now - 7200, auth_time: now - 7200, exp: now - 3600 }));
  await bad('another project (aud)', idToken(cPhone, { aud: 'someone-else' }));
  await bad('wrong issuer', idToken(cPhone, { iss: 'https://securetoken.google.com/someone-else' }));
  await bad('sign-in older than 15 minutes', idToken(cPhone, { auth_time: now - 20 * 60, iat: now - 60 }));
  await bad('auth_time in the future', idToken(cPhone, { auth_time: now + 600 }));
  await bad('not a phone sign-in', idToken(cPhone, { firebase: { sign_in_provider: 'password' } }));
  await bad('no phone number', idToken(cPhone, { phone_number: undefined }));
  await bad('no subject', idToken(cPhone, { sub: '' }));
  await bad('signed by another key under our kid', idToken(cPhone, {}, { key: IMPOSTOR_KEY }));
  await bad('HS256 token', idToken(cPhone, {}, { key: 'shared-secret', algorithm: 'HS256' }));
  await bad('garbage', 'not.a.token-at-all-xxxxxxxx');
  const before = certFetches;
  await bad('unknown kid', idToken(cPhone, {}, { kid: 'rotated-away' }));
  check('… refetched the certificates once', before + 1, certFetches);
  certsDown = true;
  const down = await api('POST', '/api/customer/auth/otp/verify', null, { phone: cPhone, firebase_id_token: idToken(cPhone, {}, { kid: 'new-kid' }) });
  check('certificate endpoint down → 503 otp_provider_error', [503, 'otp_provider_error'], [down.status, down.body?.error]);
  certsDown = false;

  // Agent signup end to end.
  const masters = (await api('GET', '/api/masters')).body;
  const COMM = masters.communities[0].id;
  const av = await api('POST', '/api/auth/otp/verify', null, { phone: aPhone, firebase_id_token: idToken(aPhone) });
  check('agent verify → verification token', true, typeof av.body?.verification_token === 'string');
  const aSignup = await api('POST', '/api/auth/signup', null, {
    full_name: 'Firebase Agent', phone: aPhone, password: 'secret123', agency_name: 'FB Bureau', community_ids: [COMM], phone_verification_token: av.body?.verification_token,
  });
  check('agent signup 201', 201, aSignup.status);
  check('agent token for another number → phone_mismatch', 'phone_mismatch', (await api('POST', '/api/auth/otp/verify', null, { phone: aPhone, firebase_id_token: idToken(randomPhone()) })).body?.error);
  check('registered agent number → 409 phone_taken before any SMS', 409, (await api('POST', '/api/auth/otp/send', null, { phone: aPhone, firebase: true })).status);

  // ======================================================================
  step('3. Razorpay — checkout, signature, capture');
  const admin = (await api('POST', '/api/auth/login', null, { phone: ADMIN_PHONE, password: ADMIN_PASS })).body?.token;
  const AGENT_ID = aSignup.body?.agent?.id;
  check('admin activates the agent', 200, (await api('POST', `/api/admin/agents/${AGENT_ID}/activate`, admin)).status);

  /** A new customer linked to the agent, with one (unpaid) profile → {token, profileId}. */
  async function customerWithProfile(name) {
    const phone = randomPhone();
    const ver = await api('POST', '/api/customer/auth/otp/verify', null, { phone, firebase_id_token: idToken(phone) });
    const su = await api('POST', '/api/customer/auth/signup', null, { full_name: name, phone, phone_verification_token: ver.body?.verification_token });
    const token = su.body?.token;
    await api('POST', '/api/customer/agent', token, { agent_id: AGENT_ID });
    const p = await apiForm('/api/customer/my-profiles', token, { full_name: name, gender: 'bride', dob: '1997-05-05', community_id: COMM });
    return { token, profileId: p.body?.profile?.id, phone };
  }
  const paidOf = async (c) => (await api('GET', '/api/customer/my-profiles', c.token)).body?.profiles?.find((x) => x.id === c.profileId)?.paid;

  const c1 = await customerWithProfile('Razor One');
  assertTrue('customer + profile ready', c1.token && c1.profileId);
  check('me says payment_provider razorpay', 'razorpay', (await api('GET', '/api/customer/auth/me', c1.token)).body?.customer?.payment_provider);
  const o1 = await api('POST', `/api/customer/my-profiles/${c1.profileId}/payment`, c1.token);
  check('order 201', 201, o1.status);
  const P1 = o1.body?.payment;
  check('… razorpay, key id, ₹150 in paise', ['razorpay', RZP_KEY, 15000], [P1?.provider, P1?.key_id, P1?.amount_paise]);
  const created = rzp.calls.find((c) => c.method === 'POST' && c.url === '/v1/orders');
  check('Razorpay got the order with our key', [true, 15000, 'INR', String(c1.profileId)], [created?.authOk, created?.body?.amount, created?.body?.currency, created?.body?.notes?.profile_id]);
  check('… order id handed to the app', rzp.orders.has(P1?.order_id), true);

  const badSig = await api('POST', `/api/customer/payments/${P1.id}/confirm`, c1.token, { provider_payment_id: 'pay_A1', signature: 'deadbeef' });
  check('wrong signature → 400 payment_verification_failed', [400, 'payment_verification_failed'], [badSig.status, badSig.body?.error]);
  check('… still unpaid', false, await paidOf(c1));
  rzpPay(P1.order_id, 'pay_A1');
  rzp.payments.set('pay_A1', 'authorized'); // as if the account were on manual capture
  const conf = await api('POST', `/api/customer/payments/${P1.id}/confirm`, c1.token, { provider_payment_id: 'pay_A1', signature: checkoutSignature(P1.order_id, 'pay_A1') });
  check('valid signature → 200 paid', [200, 'paid'], [conf.status, conf.body?.payment?.status]);
  check('… profile paid', true, conf.body?.profile?.paid);
  const capture = rzp.calls.find((c) => c.method === 'POST' && c.url === '/v1/payments/pay_A1/capture');
  check('an authorized payment gets captured for the full amount', 15000, capture?.body?.amount);
  check('confirm again is idempotent', 'paid', (await api('POST', `/api/customer/payments/${P1.id}/confirm`, c1.token, { provider_payment_id: 'pay_A1', signature: checkoutSignature(P1.order_id, 'pay_A1') })).body?.payment?.status);
  check('new checkout after paying → 409 already_paid', 'already_paid', (await api('POST', `/api/customer/my-profiles/${c1.profileId}/payment`, c1.token)).body?.error);
  const captures = rzp.calls.filter((c) => c.url === '/v1/payments/pay_A1/capture').length;
  check('… captured only once (the second confirm saw it captured)', 1, captures);

  // ======================================================================
  step('4. Razorpay — safety net (the app died after paying)');
  const c2 = await customerWithProfile('Razor Two');
  const o2 = (await api('POST', `/api/customer/my-profiles/${c2.profileId}/payment`, c2.token)).body?.payment;
  rzpPay(o2.order_id, 'pay_B1'); // paid at Razorpay, but the app never confirmed
  const ordersBefore = rzp.orders.size;
  const retry = await api('POST', `/api/customer/my-profiles/${c2.profileId}/payment`, c2.token);
  check('starting a new checkout → 409 already_paid', [409, 'already_paid'], [retry.status, retry.body?.error]);
  check('… no second Razorpay order', ordersBefore, rzp.orders.size);
  check('… profile paid', true, await paidOf(c2));
  check('… the old order was confirmed with Razorpay', true, rzp.calls.some((c) => c.url === `/v1/orders/${o2.order_id}/payments`));

  const c2b = await customerWithProfile('Razor Two B');
  const o2b = (await api('POST', `/api/customer/my-profiles/${c2b.profileId}/payment`, c2b.token)).body?.payment;
  const o2c = await api('POST', `/api/customer/my-profiles/${c2b.profileId}/payment`, c2b.token);
  check('an unpaid open order does not block a new one', 201, o2c.status);
  assertTrue('… a different order', o2c.body?.payment?.order_id && o2c.body.payment.order_id !== o2b.order_id);

  // ======================================================================
  step('5. Razorpay — webhook');
  const c3 = await customerWithProfile('Razor Three');
  const o3 = (await api('POST', `/api/customer/my-profiles/${c3.profileId}/payment`, c3.token)).body?.payment;
  check('no signature → 400', [400, 'invalid_signature'], await webhook(orderPaidEvent(o3.order_id, 'pay_C1'), { signature: null }).then((r) => [r.status, r.body?.error]));
  check('wrong secret → 400', 400, (await webhook(orderPaidEvent(o3.order_id, 'pay_C1'), { secret: 'nope' })).status);
  check('still unpaid', false, await paidOf(c3));
  check('other events are acknowledged and ignored', [200, true], await webhook({ event: 'payment.authorized', payload: {} }).then((r) => [r.status, r.body?.ignored]));
  check('unknown orders are acknowledged and ignored', [200, true], await webhook(orderPaidEvent('order_unknown', 'pay_X')).then((r) => [r.status, r.body?.ignored]));
  const hook = await webhook(orderPaidEvent(o3.order_id, 'pay_C1'));
  check('order.paid → 200 paid', [200, 'paid'], [hook.status, hook.body?.status]);
  check('… profile paid', true, await paidOf(c3));
  check('replay is harmless', [200, 'paid'], await webhook(orderPaidEvent(o3.order_id, 'pay_C1')).then((r) => [r.status, r.body?.status]));
  const c3b = await customerWithProfile('Razor Three B');
  const o3b = (await api('POST', `/api/customer/my-profiles/${c3b.profileId}/payment`, c3b.token)).body?.payment;
  const captured = { event: 'payment.captured', payload: { payment: { entity: { id: 'pay_C2', order_id: o3b.order_id, status: 'captured' } } } };
  check('payment.captured settles too', 'paid', (await webhook(captured)).body?.status);
  check('… profile paid', true, await paidOf(c3b));

  // ======================================================================
  step('6. Razorpay — a second payment for a paid profile is refund_due');
  const c4 = await customerWithProfile('Razor Four');
  const first = (await api('POST', `/api/customer/my-profiles/${c4.profileId}/payment`, c4.token)).body?.payment;
  const second = (await api('POST', `/api/customer/my-profiles/${c4.profileId}/payment`, c4.token)).body?.payment;
  check('second order paid by webhook', 'paid', (await webhook(orderPaidEvent(second.order_id, 'pay_D2'))).body?.status);
  check('first order completing later → refund_due', 'refund_due', (await webhook(orderPaidEvent(first.order_id, 'pay_D1'))).body?.status);
  const late = await api('POST', `/api/customer/payments/${first.id}/confirm`, c4.token, { provider_payment_id: 'pay_D1', signature: checkoutSignature(first.order_id, 'pay_D1') });
  check('the app confirming it → 409 already_paid (the app treats that as done)', [409, 'already_paid'], [late.status, late.body?.error]);
  const stats = (await api('GET', '/api/admin/stats', admin)).body?.stats;
  assertTrue('admin stats count refunds_due', (stats?.refunds_due ?? 0) >= 1);

  // ======================================================================
  step('7. Fast2SMS OTP (SPEC §9.19 C)');
  const f = (method, path, token, body) => apiAt(F2S_BASE, method, path, token, body);
  assertTrue('second API started with OTP provider fast2sms', /OTP provider fast2sms/.test(apiLog));
  const fPhone = randomPhone();
  const fSend = await f('POST', '/api/customer/auth/otp/send', null, { phone: fPhone, firebase: true });
  check('send 200 (the 3.1.0 firebase flag is ignored)', 200, fSend.status);
  check('… provider fast2sms, sent, not mock', ['fast2sms', true, false], [fSend.body?.provider, fSend.body?.sent, fSend.body?.mock]);
  check('… never echoes the code', undefined, fSend.body?.mock_code);
  check('… no firebase options', undefined, fSend.body?.firebase);
  const call = f2s.calls.at(-1);
  check('Fast2SMS got a POST with our key in the authorization header', ['POST', 'f2s_fake_key'], [call?.method, call?.auth]);
  check('… route otp, the number, flash 0', ['otp', fPhone, 0], [call?.body?.route, call?.body?.numbers, call?.body?.flash]);
  assertTrue('… a 6-digit numeric code', /^\d{6}$/.test(call?.body?.variables_values ?? ''));
  const smsCode = call?.body?.variables_values;
  const wrong = smsCode === '000000' ? '111111' : '000000';
  check('wrong code → invalid_otp', [400, 'invalid_otp'], await f('POST', '/api/customer/auth/otp/verify', null, { phone: fPhone, code: wrong }).then((r) => [r.status, r.body?.error]));
  const fVerify = await f('POST', '/api/customer/auth/otp/verify', null, { phone: fPhone, code: smsCode });
  check('the SMS code → new: true', true, fVerify.body?.new);
  check('… signup with it 201', 201, (await f('POST', '/api/customer/auth/signup', null, { full_name: 'Fast Two', phone: fPhone, phone_verification_token: fVerify.body?.verification_token })).status);
  check('a code is good once', 410, (await f('POST', '/api/customer/auth/otp/verify', null, { phone: fPhone, code: smsCode })).status);

  const oPhone = randomPhone();
  check('a 3.0.0 app (no flag) works too', ['fast2sms', 200], await f('POST', '/api/auth/otp/send', null, { phone: oPhone }).then((r) => [r.body?.provider, r.status]));
  const aCode = f2s.calls.at(-1)?.body?.variables_values;
  check('agent signup code verifies', true, typeof (await f('POST', '/api/auth/otp/verify', null, { phone: oPhone, code: aCode })).body?.verification_token === 'string');
  check('a Firebase token is refused while the provider is fast2sms', 'otp_provider_mismatch', (await f('POST', '/api/auth/otp/verify', null, { phone: oPhone, firebase_id_token: idToken(oPhone) })).body?.error);

  f2s.fail = true;
  const bPhone = randomPhone();
  const failed = await f('POST', '/api/customer/auth/otp/send', null, { phone: bPhone });
  check('Fast2SMS refuses (no balance) → 503 otp_provider_error', [503, 'otp_provider_error'], [failed.status, failed.body?.error]);
  f2s.fail = false;
  check('… nothing stored: an immediate retry is not held by the cooldown', 200, (await f('POST', '/api/customer/auth/otp/send', null, { phone: bPhone })).status);
  check('… and the next send right after is', 429, (await f('POST', '/api/customer/auth/otp/send', null, { phone: bPhone })).status);

  // ======================================================================
  step('10. StartMessaging OTP (SPEC §9.19 C2)');
  const sx = (method, path, token, body) => apiAt(SM_BASE, method, path, token, body);
  assertTrue('third API started with OTP provider startmessaging', /OTP provider startmessaging/.test(apiLog));
  const sPhone = randomPhone();
  const sSend = await sx('POST', '/api/customer/auth/otp/send', null, { phone: sPhone, firebase: true });
  check('send 200, provider startmessaging, no echo', [200, 'startmessaging', false, undefined], [sSend.status, sSend.body?.provider, sSend.body?.mock, sSend.body?.mock_code]);
  const sCall = sm.calls.at(-1);
  check('StartMessaging got POST /otp/send with our key', ['POST', '/otp/send', 'sm_live_fake'], [sCall?.method, sCall?.url, sCall?.key]);
  check('… E.164 number, the template, app name Wedbook', [`+91${sPhone}`, 'tpl_otp_1', 'Wedbook'], [sCall?.body?.phoneNumber, sCall?.body?.templateId, sCall?.body?.variables?.appName]);
  assertTrue('… our 6-digit code', /^\d{6}$/.test(sCall?.body?.variables?.otp ?? ''));
  const sVerify = await sx('POST', '/api/customer/auth/otp/verify', null, { phone: sPhone, code: sCall?.body?.variables?.otp });
  check('the delivered code verifies → new: true', true, sVerify.body?.new);
  const aPhone2 = randomPhone();
  check('agent signup send works too (any app version)', 200, (await sx('POST', '/api/auth/otp/send', null, { phone: aPhone2 })).status);
  sm.fail = true;
  const sBad = await sx('POST', '/api/customer/auth/otp/send', null, { phone: randomPhone() });
  check('StartMessaging refuses → 503 otp_provider_error', [503, 'otp_provider_error'], [sBad.status, sBad.body?.error]);
  sm.fail = false;
  assertTrue('… the reason is logged', /startmessaging rejected the send: 402/.test(apiLog));

  // ======================================================================
  step('8. Reviewer login (SPEC §9.19 F)');
  const rs = await api('POST', '/api/customer/auth/otp/send', null, { phone: REVIEW_PHONE });
  check('firebase server, review number, even an old app → 200 code flow', [200, 'review', true], [rs.status, rs.body?.provider, rs.body?.sent]);
  check('… no code echoed, no firebase options', [undefined, undefined], [rs.body?.mock_code, rs.body?.firebase]);
  check('… wrong code → invalid_otp', 'invalid_otp', (await api('POST', '/api/customer/auth/otp/verify', null, { phone: REVIEW_PHONE, code: '135790' })).body?.error);
  const rv = await api('POST', '/api/customer/auth/otp/verify', null, { phone: REVIEW_PHONE, code: REVIEW_CODE });
  check('… the fixed code → new: true', true, rv.body?.new);
  check('… signup 201', 201, (await api('POST', '/api/customer/auth/signup', null, { full_name: 'Demo Customer', phone: REVIEW_PHONE, phone_verification_token: rv.body?.verification_token })).status);
  await new Promise((r) => setTimeout(r, 100));
  check('agent signup for the review number is unaffected (firebase)', 'firebase', (await api('POST', '/api/auth/otp/send', null, { phone: REVIEW_PHONE, firebase: true })).body?.provider);
  const before2 = f2s.calls.length;
  const rf = await f('POST', '/api/customer/auth/otp/send', null, { phone: REVIEW_PHONE2 });
  check('fast2sms server, review number → no SMS sent', [200, 'review', before2], [rf.status, rf.body?.provider, f2s.calls.length]);
  const rl = await f('POST', '/api/customer/auth/otp/verify', null, { phone: REVIEW_PHONE2, code: REVIEW_CODE });
  check('… the fixed code verifies', true, rl.body?.new === true || typeof rl.body?.token === 'string');

  // ======================================================================
  step('9. Public website (SPEC §9.19 E)');
  const page = async (path) => {
    const r = await fetch(`${BASE}${path}`);
    return { status: r.status, type: r.headers.get('content-type') || '', text: await r.text() };
  };
  const home = await page('/');
  check('home 200 html', [200, true], [home.status, home.type.startsWith('text/html')]);
  assertTrue('… download button', home.text.includes('/download/wedbook-matrimony.apk') && home.text.includes('/download/wedbook-agent.apk'));
  assertTrue('… the fee', home.text.includes('₹150'));
  for (const link of ['/about', '/contact', '/pricing', '/terms', '/privacy', '/refunds', '/shipping']) {
    assertTrue(`… links to ${link}`, home.text.includes(`href="${link}"`));
    const pg = await page(link);
    check(`${link} 200`, 200, pg.status);
  }
  const contact = await page('/contact');
  assertTrue('contact shows the business, phone and email', contact.text.includes('Test Bureau Pvt Ltd') && contact.text.includes('9036384100') && contact.text.includes('help@example.com'));
  assertTrue('… no address line when SITE_ADDRESS is empty', !contact.text.includes('<li></li>'));
  assertTrue('refund policy: full refund until approved', (await page('/refunds')).text.includes('until your agent approves your profile'));
  const logo = await fetch(`${BASE}/site/logo.png`);
  check('logo png', [200, 'image/png'], [logo.status, logo.headers.get('content-type')]);
  const missing = await page('/download/wedbook-matrimony.apk');
  check('download before the APK is copied → 404 page', [404, true], [missing.status, missing.type.startsWith('text/html')]);
  mkdirSync(join(tmp, 'uploads', 'downloads'), { recursive: true });
  writeFileSync(join(tmp, 'uploads', 'downloads', 'wedbook-matrimony.apk'), Buffer.from('PK fake apk'));
  const apk = await fetch(`${BASE}/download/wedbook-matrimony.apk`);
  check('download → the APK', [200, 'application/vnd.android.package-archive'], [apk.status, apk.headers.get('content-type')]);
  assertTrue('… as an attachment', /attachment; filename="wedbook-matrimony.apk"/.test(apk.headers.get('content-disposition') || ''));
  check('unknown download → 404', 404, (await page('/download/other.apk')).status);
  check('path tricks → 404', 404, (await page('/download/..%2F..%2Fpackage.json')).status);
  const apiMiss = await api('GET', '/api/no-such-route');
  check('unknown API routes still answer JSON 404', [404, 'not_found'], [apiMiss.status, apiMiss.body?.error]);
} catch (e) {
  failures.push(`crashed: ${e.stack}`);
  console.log(red(e.stack));
} finally {
  shutdown();
}

console.log(`\n${bold(`====== ${pass}/${pass + failures.length} passed ======`)}`);
if (failures.length) {
  console.log(red(failures.join('\n')));
  console.log('\nAPI log:\n' + apiLog.slice(-3000));
  process.exit(1);
}
