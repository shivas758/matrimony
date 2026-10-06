/**
 * End-to-end smoke test for the Mediator (matrimony agents) API.
 *
 *   node test/smoke.mjs                    # against http://localhost:3000
 *   BASE=https://your-domain node test/smoke.mjs
 *
 * Asserts every business rule in CLAUDE.md and SPEC §3 / §9 against a running
 * API (steps 28–36 cover the Gandharva customer side: OTP, clients, browse
 * scope, interests, agent change, the registration form, the new profile
 * fields and the admin customer screens).
 * Safe to re-run: it creates its own agents/customers/profiles with random
 * phones and tolerates rows left by earlier runs. Needs the mock OTP provider
 * (OTP_PROVIDER=mock with OTP_MOCK_ECHO on, the default) — or set OTP_CODE to
 * the code a real provider would send.
 *
 * The credential endpoints are limited to 50 calls per 15 min per client
 * address. The API trusts one proxy hop (Caddy), so every step here tags its
 * requests with a fresh X-Forwarded-For address: the limiter counts each step
 * on its own and one run never bleeds into the next. Behind Caddy the header
 * is ignored (Caddy appends the real address), which is why production is
 * never smoke-tested.
 */

const BASE = (process.env.BASE || 'http://localhost:3000').replace(/\/+$/, '');
const ADMIN_PHONE = process.env.ADMIN_PHONE || '9999999999';
const ADMIN_PASS = process.env.ADMIN_PASS || 'ChangeMe@123';
// Fallback when the send response carries no mock_code (OTP_MOCK_ECHO=false).
const OTP_CODE = process.env.OTP_CODE || '123456';

let pass = 0;
const failures = [];

// Per-step client address (see the header). 10.x.y.z, unique per run and step.
const RUN_OCTET = 1 + Math.floor(Math.random() * 254);
let stepNo = 0;
let clientIp = `10.${RUN_OCTET}.0.1`;
const forwardedFor = () => ({ 'X-Forwarded-For': clientIp });

const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;

function check(label, expected, actual) {
  const same = JSON.stringify(expected) === JSON.stringify(actual);
  if (same) {
    pass++;
    console.log(`  ${green('PASS')} ${label}`);
  } else {
    failures.push(label);
    console.log(`  ${red('FAIL')} ${label}`);
    console.log(`       expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertTrue(label, cond, detail) {
  check(label, true, Boolean(cond));
  if (!cond && detail) console.log(`       ${detail}`);
}

function step(title) {
  // A fresh client address per step keeps the auth limiter out of the way.
  stepNo++;
  clientIp = `10.${RUN_OCTET}.${Math.floor(stepNo / 250)}.${(stepNo % 250) + 1}`;
  console.log(`\n${bold(title)}`);
}

/** JSON request helper -> { status, body }. */
async function api(method, path, token, body) {
  const headers = forwardedFor();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = text;
  }
  return { status: res.status, body: parsed };
}

/** Multipart helper for profile create / photo upload. */
async function apiForm(method, path, token, fields, files = []) {
  const form = new FormData();
  for (const [k, v] of Object.entries(fields)) if (v !== undefined && v !== null) form.append(k, String(v));
  for (const f of files) form.append('photos', new Blob([f.buffer], { type: f.type || 'image/jpeg' }), f.name);
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { ...forwardedFor(), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: form,
  });
  const text = await res.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = text;
  }
  return { status: res.status, body: parsed };
}

/** Raw binary/HTML fetch -> { status, headers, buffer, text }. */
async function raw(url, { method = 'GET', token, json, form } = {}) {
  const headers = forwardedFor();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (json !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(url, {
    method,
    headers,
    body: form ?? (json === undefined ? undefined : JSON.stringify(json)),
  });
  const buffer = Buffer.from(await res.arrayBuffer());
  return { status: res.status, headers: res.headers, buffer, text: buffer.toString('utf8') };
}

// ---------------------------------------------------------------- OTP helpers (SPEC §9.1)

/** The code the mock provider echoed, or the configured fallback. */
const codeFrom = (send) => send.body?.mock_code || OTP_CODE;

/** Agent signup proof: /auth/otp/send + /auth/otp/verify -> {send, verify, token}. */
async function agentOtpToken(phone) {
  const send = await api('POST', '/api/auth/otp/send', null, { phone });
  const verify = await api('POST', '/api/auth/otp/verify', null, { phone, code: codeFrom(send) });
  return { send, verify, token: verify.body?.verification_token };
}

/** Full agent signup (send → verify → signup) -> the /auth/signup response. */
async function signupAgent(fields) {
  const { token } = await agentOtpToken(fields.phone);
  return api('POST', '/api/auth/signup', null, { ...fields, phone_verification_token: token });
}

/** Customer OTP round trip -> the /customer/auth/otp/verify response (login or {new, verification_token}). */
async function customerOtp(phone) {
  const send = await api('POST', '/api/customer/auth/otp/send', null, { phone });
  const verify = await api('POST', '/api/customer/auth/otp/verify', null, { phone, code: codeFrom(send) });
  return { send, verify };
}

/** Full Gandharva signup (send → verify → signup) -> the /customer/auth/signup response. */
async function signupCustomer({ full_name, phone, agent_phone }) {
  const { verify } = await customerOtp(phone);
  return api('POST', '/api/customer/auth/signup', null, {
    full_name, phone, agent_phone, phone_verification_token: verify.body?.verification_token,
  });
}

/** A real-sized JPEG when sharp is around (it is a backend dependency); the tiny one otherwise. */
async function samplePhoto(label = 'Smoke') {
  try {
    const { default: sharp } = await import('sharp');
    const svg = `<svg width="600" height="750" xmlns="http://www.w3.org/2000/svg">
      <rect width="600" height="750" fill="#c9b8a8"/><circle cx="300" cy="300" r="140" fill="#f0e2d6"/>
      <text x="300" y="640" font-family="DejaVu Sans, Arial, sans-serif" font-size="40" text-anchor="middle" fill="#4a1a29">${label}</text>
    </svg>`;
    return await sharp(Buffer.from(svg)).jpeg({ quality: 85 }).toBuffer();
  } catch {
    return TINY_JPEG;
  }
}

/** Unique-ish Indian mobile number per run. */
const phones = new Set();
function randomPhone(prefix) {
  let p;
  do {
    p = prefix + String(Math.floor(Math.random() * 1e9)).padStart(9, '0');
  } while (phones.has(p));
  phones.add(p);
  return p;
}

/** Smallest valid JPEG we can synthesise without extra deps: a 2x2 red pixel. */
const TINY_JPEG = Buffer.from(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a' +
    'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAACAAIBAREA/8QAHwAAAQUBAQEB' +
    'AQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1Fh' +
    'ByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZ' +
    'WmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXG' +
    'x8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oACAEBAAA/APn+v//Z',
  'base64',
);

async function main() {
  console.log(bold(`Mediator API smoke test → ${BASE}\n`));

  // ---------------------------------------------------------------- health
  step('0. Health');
  const health = await api('GET', '/api/health');
  check('health 200', 200, health.status);
  check('health ok:true', true, health.body?.ok);
  if (health.status !== 200) {
    console.log(red('\nAPI is not reachable — start it first.'));
    process.exit(1);
  }

  // ---------------------------------------------------------------- masters
  step('1. Masters (public — the signup screen needs communities)');
  const masters = await api('GET', '/api/masters');
  check('masters 200', 200, masters.status);
  const m = masters.body;
  check('27 nakshatrams seeded', 27, m.nakshatrams.length);
  check('12 zodiac signs seeded', 12, m.zodiac_signs.length);
  assertTrue('religions seeded', (m.religions?.length ?? 0) >= 5);
  assertTrue('languages seeded', (m.languages?.length ?? 0) >= 10);
  assertTrue('food habits seeded', (m.food_habits?.length ?? 0) >= 5);
  assertTrue('at least 2 communities seeded', m.communities.length >= 2);
  const COMM_A = m.communities[0].id;
  const COMM_B = m.communities[1].id;
  const EDU = m.educations[0].id;
  const PROF = m.professions[0].id;
  const MSTAT = m.marital_statuses[0].id;
  const ZOD = m.zodiac_signs[0].id;
  const NAK = m.nakshatrams[0].id;

  // ---------------------------------------------------------------- admin
  step('2. Admin login');
  const adminLogin = await api('POST', '/api/auth/login', null, { phone: ADMIN_PHONE, password: ADMIN_PASS });
  if (adminLogin.status === 429) {
    console.log(red('\nRate limited (429). The auth limiter allows 50 attempts per 15 minutes.'));
    console.log(red('Wait a few minutes and re-run, or restart the API to reset the counter.'));
    process.exit(1);
  }
  check('admin login 200', 200, adminLogin.status);
  const ADMIN = adminLogin.body?.token;
  check('role is admin', 'admin', adminLogin.body?.agent?.role);
  if (!ADMIN) {
    console.log(red(`\nAdmin login failed (${adminLogin.status}) — cannot continue.`));
    console.log(red(`Check ADMIN_PHONE / ADMIN_PASS. Response: ${JSON.stringify(adminLogin.body)}`));
    process.exit(1);
  }

  // ---------------------------------------------------------------- rule 2
  step('3. Signup creates a PENDING agent (rule 2) — after the OTP round trip (SPEC §9.1)');
  const aPhone = randomPhone('9');
  const signupA = await signupAgent({
    full_name: 'Agent A',
    phone: aPhone,
    password: 'secret123',
    agency_name: 'A Bureau',
    community_ids: [COMM_A],
  });
  check('signup 201', 201, signupA.status);
  check('new agent is pending', 'pending', signupA.body?.agent?.status);
  const A = signupA.body?.token;

  const blocked = await api('GET', '/api/profiles', A);
  check('pending agent blocked from profiles', 403, blocked.status);
  check('error code is account_pending', 'account_pending', blocked.body?.error);
  const meWhilePending = await api('GET', '/api/auth/me', A);
  check('pending agent CAN read /auth/me (waiting screen)', 200, meWhilePending.status);

  step('4. Admin activates agent A');
  const pendingList = await api('GET', '/api/admin/agents?status=pending', ADMIN);
  const aRow = pendingList.body?.agents?.find((x) => x.phone === aPhone);
  assertTrue('agent A appears in the pending list', Boolean(aRow));
  if (!aRow) {
    console.log(red('\nCannot continue without the new agent. Is the admin list route working?'));
    process.exit(1);
  }
  const activated = await api('POST', `/api/admin/agents/${aRow.id}/activate`, ADMIN);
  check('activate 200', 200, activated.status);
  check('status now active', 'active', activated.body?.agent?.status);
  check('agent A can now list profiles', 200, (await api('GET', '/api/profiles', A)).status);

  // ---------------------------------------------------------------- other agents
  step('5. Agent B in a DIFFERENT community, agent C in the same one');
  const bPhone = randomPhone('8');
  const signupB = await signupAgent({
    full_name: 'Agent B', phone: bPhone, password: 'secret123', agency_name: 'B Bureau', community_ids: [COMM_B],
  });
  const B = signupB.body?.token;
  const B_ID = signupB.body?.agent?.id;
  check('activate B', 200, (await api('POST', `/api/admin/agents/${B_ID}/activate`, ADMIN)).status);

  const cPhone = randomPhone('7');
  const signupC = await signupAgent({
    full_name: 'Agent C', phone: cPhone, password: 'secret123', agency_name: 'C Bureau', community_ids: [COMM_A],
  });
  const C = signupC.body?.token;
  const C_ID = signupC.body?.agent?.id;
  check('activate C', 200, (await api('POST', `/api/admin/agents/${C_ID}/activate`, ADMIN)).status);

  // ---------------------------------------------------------------- upload
  step('6. Agent A uploads a profile with a photo');
  const created = await apiForm(
    'POST',
    '/api/profiles',
    A,
    {
      full_name: 'Priya Kumari', gender: 'bride', dob: '1998-04-12', height_cm: 160,
      community_id: COMM_A, education_id: EDU, profession_id: PROF, marital_status_id: MSTAT,
      zodiac_id: ZOD, nakshatram_id: NAK, city: 'Hyderabad', state: 'Telangana',
      income_text: '8 LPA', about: 'Friendly and family oriented.',
      family_details: 'Father is a retired teacher.',
      contact_name: 'Ramesh Kumar', contact_phone: '9876543210',
    },
    [{ buffer: TINY_JPEG, name: 'photo.jpg', type: 'image/jpeg' }],
  );
  check('create profile 201', 201, created.status);
  const P = created.body?.profile;
  assertTrue('profile has an id', Boolean(P?.id), JSON.stringify(created.body).slice(0, 300));
  const PID = P?.id;
  check('photo was stored and resized', 1, P?.photos?.length);
  check('uploader sees own contact_phone', '9876543210', P?.contact_phone);
  check('uploader contact_access = granted', 'granted', P?.contact_access);
  check('uploader can_edit', true, P?.can_edit);

  const photoRes = await fetch(`${BASE}${P.photos[0].url}`, { headers: { Authorization: `Bearer ${A}` } });
  check('authenticated photo fetch 200', 200, photoRes.status);
  check('photo served as JPEG', 'image/jpeg', photoRes.headers.get('content-type'));
  check('unauthenticated photo fetch 401', 401, (await fetch(`${BASE}${P.photos[0].url}`)).status);

  // ---------------------------------------------------------------- rule 1
  step('7. Community visibility (rule 1)');
  const bList = await api('GET', '/api/profiles', B);
  check('agent B (other community) does not see it', 0, bList.body.profiles.filter((x) => x.id === PID).length);
  check('agent B detail = 404', 404, (await api('GET', `/api/profiles/${PID}`, B)).status);
  const aList = await api('GET', '/api/profiles', A);
  check('agent A sees it', 1, aList.body.profiles.filter((x) => x.id === PID).length);
  const listed = aList.body.profiles.find((x) => x.id === PID);
  check('list response omits contact_phone', undefined, listed.contact_phone);
  check('list response omits contact_name', undefined, listed.contact_name);
  const adminList = await api('GET', '/api/profiles', ADMIN);
  check('admin sees all communities', 1, adminList.body.profiles.filter((x) => x.id === PID).length);

  // ---------------------------------------------------------------- rules 3 & 4
  step('8. Contact details are hidden in-app (rule 4)');
  const cView = await api('GET', `/api/profiles/${PID}`, C);
  check('agent C can see the profile', 200, cView.status);
  check('contact_phone is OMITTED, not blanked', false, 'contact_phone' in cView.body.profile);
  check('contact_name is OMITTED', false, 'contact_name' in cView.body.profile);
  check('contact_access = none', 'none', cView.body.profile.contact_access);
  check('uploader identity hidden from C', false, 'uploaded_by' in cView.body.profile);
  // Since 005 family details are on request too (SPEC §9.8).
  check('family_details is OMITTED for C (on request now)', false, 'family_details' in cView.body.profile);
  check('uploader still sees family_details', 'Father is a retired teacher.', P?.family_details);

  const req1 = await api('POST', `/api/profiles/${PID}/contact-request`, C, { note: 'Client interested' });
  check('contact request 201', 201, req1.status);
  const CR_ID = req1.body?.contact_request?.id;
  check('duplicate request 409', 409, (await api('POST', `/api/profiles/${PID}/contact-request`, C, {})).status);
  check('contact_access = pending', 'pending', (await api('GET', `/api/profiles/${PID}`, C)).body.profile.contact_access);
  check(
    'agent B cannot request an invisible profile',
    404,
    (await api('POST', `/api/profiles/${PID}/contact-request`, B, {})).status,
  );

  step('9. Uploader approves — 15-day window');
  const inbox = await api('GET', '/api/contact-requests?box=inbox', A);
  check('request is in A inbox', 1, inbox.body.contact_requests.filter((r) => r.id === CR_ID).length);
  check('inbox shows who is asking', 'Agent C', inbox.body.contact_requests.find((r) => r.id === CR_ID)?.requester?.full_name);
  const sent = await api('GET', '/api/contact-requests?box=sent', C);
  check('sent box hides the uploader identity', undefined, sent.body.contact_requests[0]?.requester);

  check('unrelated agent cannot approve', 403, (await api('POST', `/api/contact-requests/${CR_ID}/approve`, B)).status);
  const approved = await api('POST', `/api/contact-requests/${CR_ID}/approve`, A);
  check('approve 200', 200, approved.status);
  check('days_left is 15', 15, approved.body.contact_request.days_left);
  const cAfter = await api('GET', `/api/profiles/${PID}`, C);
  check('C now sees contact_phone', '9876543210', cAfter.body.profile.contact_phone);
  check('C now sees contact_name', 'Ramesh Kumar', cAfter.body.profile.contact_name);
  check('C now sees family_details', 'Father is a retired teacher.', cAfter.body.profile.family_details);
  check('contact_access = granted', 'granted', cAfter.body.profile.contact_access);
  assertTrue('contact_expires_at is set', Boolean(cAfter.body.profile.contact_expires_at));
  check('re-approving 409', 409, (await api('POST', `/api/contact-requests/${CR_ID}/approve`, A)).status);

  step('10. Revoke cuts access immediately');
  check('agent C cannot revoke their own grant', 403, (await api('POST', `/api/contact-requests/${CR_ID}/revoke`, C)).status);
  check('admin revoke 200', 200, (await api('POST', `/api/contact-requests/${CR_ID}/revoke`, ADMIN)).status);
  const cRevoked = await api('GET', `/api/profiles/${PID}`, C);
  check('contact_phone gone after revoke', false, 'contact_phone' in cRevoked.body.profile);
  check('contact_access back to none', 'none', cRevoked.body.profile.contact_access);
  check('app can tell it was revoked', 'revoked', cRevoked.body.profile.contact_request_status);

  // ---------------------------------------------------------------- rules 3, 5, 6
  step('11. Shares are masked and logged (rules 3, 5, 6)');
  const share = await api('POST', `/api/profiles/${PID}/share`, C, { method: 'whatsapp' });
  check('share 200', 200, share.status);
  const shareUrl = share.body.share_url;
  const tokenId = share.body.share_token_id;
  const waText = share.body.whatsapp_text || '';
  assertTrue('share text has no contact phone', !waText.includes('9876543210'), waText);
  assertTrue('share text has no contact name', !waText.includes('Ramesh Kumar'), waText);
  assertTrue('share text has no uploader identity', !waText.includes('Agent A') && !waText.includes('A Bureau'), waText);
  assertTrue('share text names the profile', waText.includes('Priya Kumari'), waText);

  const pubRes = await fetch(shareUrl);
  const html = await pubRes.text();
  check('public page 200 without auth', 200, pubRes.status);
  check('public page is noindex', 'noindex, nofollow', pubRes.headers.get('x-robots-tag'));
  assertTrue('public page has no contact phone', !html.includes('9876543210'));
  assertTrue('public page has no contact name', !html.includes('Ramesh Kumar'));
  assertTrue('public page has no uploader name', !html.includes('Agent A'));
  assertTrue('public page has no family details', !html.includes('retired teacher'));
  assertTrue('public page shows the profile', html.includes('Priya Kumari'));
  assertTrue('public page shows community/education', html.includes('Community') || html.includes('Education'));
  assertTrue('public page has the masked footer', html.includes('Contact your agent for details'));

  const photoIdMatch = html.match(/\/p\/[A-Za-z0-9_-]+\/photo\/(\d+)/);
  assertTrue('public page links a watermarked photo', Boolean(photoIdMatch));
  if (photoIdMatch) {
    const wmRes = await fetch(`${shareUrl}/photo/${photoIdMatch[1]}`);
    const wmBuf = Buffer.from(await wmRes.arrayBuffer());
    check('watermarked photo 200 without auth', 200, wmRes.status);
    assertTrue('watermarked photo is a JPEG', wmBuf[0] === 0xff && wmBuf[1] === 0xd8);
  }

  const dlRes = await fetch(`${BASE}/api/profiles/${PID}/share`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${C}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ method: 'download' }),
  });
  const dlBuf = Buffer.from(await dlRes.arrayBuffer());
  check('download card 200', 200, dlRes.status);
  assertTrue(`download card is a JPEG (${dlBuf.length} bytes)`, dlBuf[0] === 0xff && dlBuf[1] === 0xd8);
  assertTrue('download card is not empty', dlBuf.length > 5000, `${dlBuf.length} bytes`);

  check('uploader deactivates the link', 200, (await api('POST', `/api/share-tokens/${tokenId}/deactivate`, A)).status);
  check('deactivated link is 404', 404, (await fetch(shareUrl)).status);

  const shareLogs = await api('GET', `/api/admin/logs/shares?profile_id=${PID}`, ADMIN);
  check('both shares were logged', 2, shareLogs.body.logs.length);
  check('log records the sharing agent', 'Agent C', shareLogs.body.logs[0].agent_name);

  // ---------------------------------------------------------------- shortlists
  step('12. Shortlists');
  const sl = await api('POST', `/api/profiles/${PID}/shortlist`, C, { client_label: "Ramesh's daughter" });
  check('shortlist 201', 201, sl.status);
  const groups = (await api('GET', '/api/shortlists', C)).body.groups;
  check('grouped by client label', "Ramesh's daughter", groups[0]?.client_label);
  check('group has 1 profile', 1, groups[0]?.profiles?.length);
  check('duplicate shortlist 409', 409, (await api('POST', `/api/profiles/${PID}/shortlist`, C, { client_label: "Ramesh's daughter" })).status);
  check('delete shortlist 200', 200, (await api('DELETE', `/api/shortlists/${sl.body.shortlist.id}`, C)).status);

  // ---------------------------------------------------------------- filters
  step('13. Filters');
  const has = async (qs, token = A) =>
    (await api('GET', `/api/profiles?${qs}`, token)).body.profiles.filter((x) => x.id === PID).length;
  check('gender=bride finds it', 1, await has('gender=bride'));
  check('gender=groom excludes it', 0, await has('gender=groom'));
  check('age 18-99 finds it', 1, await has('age_min=18&age_max=99'));
  check('age 90-99 excludes it', 0, await has('age_min=90&age_max=99'));
  check('name search finds it', 1, await has('q=Priya'));
  check('city search finds it', 1, await has('city=hyder'));
  check('wrong city excludes it', 0, await has('city=chennai'));
  check(`community_id=${COMM_A} finds it`, 1, await has(`community_id=${COMM_A}`));
  check(`education_id=${EDU} finds it`, 1, await has(`education_id=${EDU}`));
  check(`nakshatram_id=${NAK} finds it`, 1, await has(`nakshatram_id=${NAK}`));
  check('height 155-165 finds it', 1, await has('height_min=155&height_max=165'));
  check('bad age range 400', 400, (await api('GET', '/api/profiles?age_min=40&age_max=30', A)).status);

  // ---------------------------------------------------------------- edit rules
  step('14. Edit permissions and status visibility');
  check('non-uploader cannot edit', 403, (await api('PATCH', `/api/profiles/${PID}`, C, { status: 'engaged' })).status);
  check('uploader can edit', 200, (await api('PATCH', `/api/profiles/${PID}`, A, { status: 'engaged' })).status);
  check('non-active profile hidden from others', 0, await has('', C));
  check('uploader still sees own non-active upload', 1, await has('mine=true'));
  // A stale link to an engaged/married profile must stop working.
  const staleShare = await api('POST', `/api/profiles/${PID}/share`, A, { method: 'link' });
  check('link on a non-active profile 404s publicly', 404, (await fetch(staleShare.body.share_url)).status);
  await api('PATCH', `/api/profiles/${PID}`, A, { status: 'active' });
  check('the same link works again once active', 200, (await fetch(staleShare.body.share_url)).status);
  await api('PATCH', `/api/profiles/${PID}`, A, { status: 'engaged' });
  check('admin can edit anyone', 200, (await api('PATCH', `/api/profiles/${PID}`, ADMIN, { status: 'active' })).status);
  check('agent cannot upload into a foreign community', 403,
    (await apiForm('POST', '/api/profiles', A, {
      full_name: 'Wrong Community', gender: 'groom', dob: '1995-01-01', community_id: COMM_B,
    })).status);

  // ---------------------------------------------------------------- community requests
  step('15. Community change requests');
  const ccr = await api('POST', '/api/my/community-requests', C, { community_id: COMM_B });
  check('request 201', 201, ccr.status);
  check('duplicate request 409', 409, (await api('POST', '/api/my/community-requests', C, { community_id: COMM_B })).status);
  check('admin approves', 200, (await api('POST', `/api/admin/community-requests/${ccr.body.community_request.id}/approve`, ADMIN)).status);
  check('agent C now in 2 communities', 2, (await api('GET', '/api/my/communities', C)).body.communities.length);

  // ---------------------------------------------------------------- admin
  step('16. Admin-only routes and master editing');
  check('agent blocked from admin', 403, (await api('GET', '/api/admin/agents', C)).status);
  check('agent blocked from master CRUD', 403, (await api('POST', '/api/admin/masters/communities', C, { name: 'Nope' })).status);
  check('admin stats 200', 200, (await api('GET', '/api/admin/stats', ADMIN)).status);
  const newComm = `Test Community ${Date.now()}`;
  const addComm = await api('POST', '/api/admin/masters/communities', ADMIN, { name: newComm });
  check('admin adds a community', 201, addComm.status);
  check('duplicate community 409', 409, (await api('POST', '/api/admin/masters/communities', ADMIN, { name: newComm })).status);
  check('admin deactivates it', 200, (await api('PATCH', `/api/admin/masters/communities/${addComm.body.row.id}`, ADMIN, { active: false })).status);
  const mastersAfter = await api('GET', '/api/masters');
  check('deactivated community drops out of /masters', 0, mastersAfter.body.communities.filter((c) => c.id === addComm.body.row.id).length);
  check('unknown master table 400', 400, (await api('POST', '/api/admin/masters/agents', ADMIN, { name: 'x' })).status);

  // ---------------------------------------------------------------- notifications
  step('17. Notifications');
  await api('POST', `/api/profiles/${PID}/contact-request`, C, {});
  const notif = await api('GET', '/api/notifications', A);
  check('uploader has an inbox badge', 1, notif.body.counts.contact_requests_inbox);
  assertTrue('notification item describes the request', notif.body.items.some((i) => i.type === 'contact_request_received'));
  const adminNotif = await api('GET', '/api/notifications', ADMIN);
  assertTrue('admin badge counts pending work', adminNotif.body.badge >= 1);

  // ---------------------------------------------------------------- auth hardening
  step('18. Auth hardening');
  check('no token 401', 401, (await api('GET', '/api/profiles')).status);
  check('garbage token 401', 401, (await api('GET', '/api/profiles', 'garbage.token.here')).status);
  check('wrong password 401', 401, (await api('POST', '/api/auth/login', null, { phone: ADMIN_PHONE, password: 'wrong' })).status);
  check('bad signup 400', 400, (await api('POST', '/api/auth/signup', null, { full_name: 'X', phone: '123', password: 'a', community_ids: [] })).status);
  // A taken number is refused at the very first step (SPEC §9.1: 409 at /otp/send),
  // and no verification token can exist for it — so signup can never reach the row.
  const dupSend = await api('POST', '/api/auth/otp/send', null, { phone: aPhone });
  check('duplicate phone: OTP send 409', 409, dupSend.status);
  check('error code phone_taken', 'phone_taken', dupSend.body?.error);
  check('duplicate phone signup without proof 400 phone_not_verified', 'phone_not_verified',
    (await api('POST', '/api/auth/signup', null, {
      full_name: 'Dup', phone: aPhone, password: 'secret123', community_ids: [COMM_A],
    })).body?.error);
  // Regression: a number starting with "91" is NOT a country-code prefix.
  const p91 = '91' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
  const s91 = await signupAgent({
    full_name: 'Ninety One', phone: p91, password: 'secret123', community_ids: [COMM_A],
  });
  check(`phone starting with 91 (${p91}) can sign up`, 201, s91.status);
  check('stored with all 10 digits intact', p91, s91.body?.agent?.phone);
  check('login with +91 prefix normalises to the same account', 200,
    (await api('POST', '/api/auth/login', null, { phone: `+91 ${p91}`, password: 'secret123' })).status);
  check('login with 0 prefix normalises too', 200,
    (await api('POST', '/api/auth/login', null, { phone: `0${p91}`, password: 'secret123' })).status);
  check('unknown share token 404', 404, (await fetch(`${BASE}/p/deadbeefdeadbeefdeadbeef`)).status);
  check('path traversal in share token 404', 404, (await fetch(`${BASE}/p/..%2F..%2Fetc%2Fpasswd`)).status);

  step('19. Change password');
  check('wrong current password 401', 401, (await api('POST', '/api/auth/change-password', C, { current_password: 'nope', new_password: 'newpass123' })).status);
  check('change password 200', 200, (await api('POST', '/api/auth/change-password', C, { current_password: 'secret123', new_password: 'newpass123' })).status);
  check('login with the new password', 200, (await api('POST', '/api/auth/login', null, { phone: cPhone, password: 'newpass123' })).status);

  // ---------------------------------------------------------------- subcastes
  step('20. Subcastes — typed on the form, scoped to the community');
  const subName = `Chowdary${Date.now() % 100000}`; // unique per run: the DB keeps subcastes between runs
  const withSub = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Subcaste Test One', gender: 'groom', dob: '1994-06-01', community_id: COMM_A,
    subcaste_name: `  ${subName}  `,
  });
  check('profile with a typed subcaste 201', 201, withSub.status);
  check('subcaste created, trimmed and attached', subName, withSub.body?.profile?.subcaste?.name);
  const SUB_ID = withSub.body?.profile?.subcaste?.id;
  const SUB_PID = withSub.body?.profile?.id;
  const withSub2 = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Subcaste Test Two', gender: 'bride', dob: '1996-06-01', community_id: COMM_A,
    subcaste_name: subName.toLowerCase(),
  });
  check('same name in a different case reuses the row (no duplicate)', SUB_ID, withSub2.body?.profile?.subcaste?.id);
  const mastersNow = await api('GET', '/api/masters');
  check('/masters lists the subcaste with its community_id', COMM_A,
    mastersNow.body.subcastes.find((s) => s.id === SUB_ID)?.community_id);
  check('filter subcaste_id finds both profiles', 2,
    (await api('GET', `/api/profiles?subcaste_id=${SUB_ID}&limit=100`, A)).body.profiles.filter((p) => p.subcaste?.id === SUB_ID).length);
  check('list rows carry subcaste', subName,
    (await api('GET', `/api/profiles?subcaste_id=${SUB_ID}`, A)).body.profiles[0]?.subcaste?.name);
  const mismatch = await apiForm('POST', '/api/profiles', ADMIN, {
    full_name: 'Mismatch', gender: 'groom', dob: '1994-06-01', community_id: COMM_B, subcaste_id: SUB_ID,
  });
  check('subcaste from another community is rejected', 400, mismatch.status);
  check('error code is subcaste_mismatch', 'subcaste_mismatch', mismatch.body?.error);
  const patched = await api('PATCH', `/api/profiles/${SUB_PID}`, A, { subcaste_name: 'Naidu' });
  check('PATCH with a typed subcaste 200', 200, patched.status);
  check('PATCH attached the new subcaste', 'Naidu', patched.body?.profile?.subcaste?.name);
  const cleared = await api('PATCH', `/api/profiles/${SUB_PID}`, A, { subcaste_id: null });
  check('PATCH subcaste_id:null clears it', null, cleared.body?.profile?.subcaste);
  const subShare = await api('POST', `/api/profiles/${withSub2.body.profile.id}/share`, A, { method: 'link' });
  assertTrue('share text carries the subcaste', (subShare.body.whatsapp_text || '').includes(subName));
  const subPage = await (await fetch(subShare.body.share_url)).text();
  assertTrue('public page shows the subcaste', subPage.includes(subName));
  const adminSub = await api('POST', '/api/admin/masters/subcastes', ADMIN, { name: `Admin Sub ${Date.now()}`, community_id: COMM_A });
  check('admin adds a subcaste via the master editor', 201, adminSub.status);
  check('admin subcaste without community_id 400', 400,
    (await api('POST', '/api/admin/masters/subcastes', ADMIN, { name: 'x' })).status);
  check('admin can deactivate a subcaste', 200,
    (await api('PATCH', `/api/admin/masters/subcastes/${adminSub.body.row.id}`, ADMIN, { active: false })).status);

  // ---------------------------------------------------------------- AI import
  step('21. AI import (POST /profiles/parse)');
  const aiStatus = await api('GET', '/api/profiles/parse/status', A);
  check('parse status 200', 200, aiStatus.status);
  const parseText = async (text) => {
    const form = new FormData();
    form.append('text', text);
    const res = await fetch(`${BASE}/api/profiles/parse`, { method: 'POST', headers: { Authorization: `Bearer ${A}` }, body: form });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
  if (aiStatus.body?.enabled) {
    console.log(`  (ANTHROPIC_API_KEY is set — real extraction with ${aiStatus.body.model})`);
    const p = await parseText(
      'Bride: Priya Kumari, DOB 12-04-1998, Height 5\'3", Caste Kamma, Sub caste Chowdary, B.Tech, ' +
      'Software Engineer at TCS, Hyderabad, Telangana, 8 LPA. Star Rohini, Rasi Vrishabha. Contact: father Ramesh Kumar 98765 43210.',
    );
    check('parse 200', 200, p.status);
    check('extracted name', 'Priya Kumari', p.body?.draft?.full_name);
    check('extracted gender', 'bride', p.body?.draft?.gender);
    check('extracted dob normalised', '1998-04-12', p.body?.draft?.dob);
    check('height converted to cm', 160, p.body?.draft?.height_cm);
    check('phone normalised to 10 digits', '9876543210', p.body?.draft?.contact_phone);
    assertTrue('nakshatram mapped to a master id', Number.isInteger(p.body?.draft?.nakshatram_id));
    assertTrue('unknown community reported as unmatched, not guessed', p.body?.unmatched?.community === 'Kamma' || Number.isInteger(p.body?.draft?.community_id));
    const junk = await parseText('Invoice #4411 for 3 boxes of A4 paper. Total Rs 1,200. Thank you for your business.');
    check('non-bio-data is refused with 422', 422, junk.status);
    check('error code not_a_biodata', 'not_a_biodata', junk.body?.error);
  } else {
    check('parse reports disabled without a key', false, aiStatus.body?.enabled);
    const p = await parseText('anything');
    check('parse returns 503 without a key', 503, p.status);
    check('error code ai_not_configured', 'ai_not_configured', p.body?.error);
  }
  check('parse needs a file or text', 400, (await parseText('')).status);

  // ---------------------------------------------------------------- new fields
  step('22. Gothram, weight, complexion, NRI — work place / NRI place / native place / parents on request');
  const CPX = m.complexions?.[1]?.id;
  const USA = m.countries?.find((c) => c.name === 'United States')?.id;
  const UK = m.countries?.find((c) => c.name === 'United Kingdom')?.id;
  const INDIA = m.countries?.find((c) => c.name === 'India')?.id;
  assertTrue('complexions seeded (5+; step 22 adds one per run)', (m.complexions?.length ?? 0) >= 5);
  assertTrue('countries seeded (India, US, UK …)', Boolean(INDIA && USA && UK) && m.countries.length >= 20);

  const nriCreate = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Nri Test Groom', gender: 'groom', dob: '1993-02-10', height_cm: 175, weight_kg: 72,
    community_id: COMM_A, complexion_id: CPX, gothram: 'Bharadwaja',
    education_id: EDU, education_details: 'CSE, JNTU Hyderabad 2015',
    profession_id: PROF, profession_details: 'Senior engineer at Acme Corp',
    work_place: 'San Jose', work_country_id: USA, is_nri: 'true', nri_country_id: USA, nri_place: 'California',
    city: 'Nalgonda', state: 'Telangana',
    father_name: 'Venkat Rao', father_phone: '9811111111', mother_name: 'Padma Rao', mother_phone: '9822222222',
    contact_name: 'Venkat Rao', contact_phone: '9811111111', income_text: '$150k',
  });
  check('create with new fields 201', 201, nriCreate.status);
  const NP = nriCreate.body?.profile;
  const NPID = NP?.id;
  check('gothram saved', 'Bharadwaja', NP?.gothram);
  check('weight saved', 72, NP?.weight_kg);
  check('complexion resolved to master', m.complexions[1].name, NP?.complexion?.name);
  check('is_nri true', true, NP?.is_nri);
  check('NRI country resolved', 'United States', NP?.nri_country?.name);
  check('NRI place saved (uploader sees it)', 'California', NP?.nri_place);
  check('work place saved (uploader sees it)', 'San Jose', NP?.work_place);
  check('work country resolved', 'United States', NP?.work_country?.name);
  check('education details saved', 'CSE, JNTU Hyderabad 2015', NP?.education_details);
  check('uploader sees native place', 'Nalgonda', NP?.city);
  check('uploader sees father phone', '9811111111', NP?.father_phone);

  const cNri = (await api('GET', `/api/profiles/${NPID}`, C)).body.profile;
  check('other agent: native city OMITTED', false, 'city' in cNri);
  check('other agent: native state OMITTED', false, 'state' in cNri);
  check('other agent: father_name OMITTED', false, 'father_name' in cNri);
  check('other agent: father_phone OMITTED', false, 'father_phone' in cNri);
  check('other agent: mother_phone OMITTED', false, 'mother_phone' in cNri);
  // Since 005 the exact work place and NRI place are on request too (SPEC §9.8).
  check('other agent: work_place OMITTED', false, 'work_place' in cNri);
  check('other agent: nri_place OMITTED', false, 'nri_place' in cNri);
  check('other agent still sees gothram', 'Bharadwaja', cNri.gothram);
  check('other agent still sees NRI country (public location)', 'United States', cNri.nri_country?.name);
  check('other agent still sees work country (public location)', 'United States', cNri.work_country?.name);
  const listRow = (await api('GET', `/api/profiles?q=Nri%20Test`, C)).body.profiles.find((x) => x.id === NPID);
  check('list row omits native city', false, 'city' in (listRow || {}));
  check('list row omits work place', false, 'work_place' in (listRow || {}));
  check('list row omits NRI place', false, 'nri_place' in (listRow || {}));
  check('list row carries work country', 'United States', listRow?.work_country?.name);
  check('list row carries NRI country', 'United States', listRow?.nri_country?.name);

  const hasN = async (qs, token = A) =>
    (await api('GET', `/api/profiles?${qs}`, token)).body.profiles.filter((x) => x.id === NPID).length;
  check('nri=true finds it', 1, await hasN('nri=true'));
  check('nri=false excludes it', 0, await hasN('nri=false'));
  check('country_id=US finds it', 1, await hasN(`country_id=${USA}`));
  check('country_id=UK excludes it', 0, await hasN(`country_id=${UK}`));
  check('country_id=US,UK (multi) finds it', 1, await hasN(`country_id=${USA},${UK}`));
  check(`complexion_id=${CPX} finds it`, 1, await hasN(`complexion_id=${CPX}`));
  check('place filter matches work place', 1, await hasN('city=san%20jose'));
  check('height 5\'8"-5\'10" (173-178 cm) finds it', 1, await hasN('height_min=173&height_max=178'));
  check('height 150-160 excludes it', 0, await hasN('height_min=150&height_max=160'));
  check('unknown country 400', 400, (await api('PATCH', `/api/profiles/${NPID}`, A, { nri_country_id: 999999 })).status);

  const nriShare = await api('POST', `/api/profiles/${NPID}/share`, C, { method: 'whatsapp' });
  const nriText = nriShare.body?.whatsapp_text || '';
  assertTrue('share text has gothram', nriText.includes('Bharadwaja'), nriText);
  assertTrue('share text has NO work place (on request)', !nriText.includes('San Jose'), nriText);
  assertTrue('share text has NO NRI place (on request)', !nriText.includes('California'), nriText);
  assertTrue('share text has height in feet-inches', /5' 9"/.test(nriText), nriText);
  assertTrue('share text has NRI country', nriText.includes('United States'), nriText);
  assertTrue('share text has NO native place', !nriText.includes('Nalgonda'), nriText);
  assertTrue('share text has NO parent name', !nriText.includes('Venkat Rao') && !nriText.includes('Padma'), nriText);
  assertTrue('share text has NO parent phone', !nriText.includes('9811111111') && !nriText.includes('9822222222'), nriText);
  const nriHtml = await (await fetch(nriShare.body.share_url)).text();
  assertTrue('public page shows gothram', nriHtml.includes('Bharadwaja'));
  assertTrue('public page shows weight', nriHtml.includes('72 kg'));
  assertTrue('public page shows complexion', nriHtml.includes(m.complexions[1].name));
  assertTrue('public page shows the NRI country', nriHtml.includes('United States'));
  assertTrue('public page has NO work place', !nriHtml.includes('San Jose'));
  assertTrue('public page has NO NRI place', !nriHtml.includes('California'));
  assertTrue('public page shows education details', nriHtml.includes('JNTU'));
  assertTrue('public page has NO native place', !nriHtml.includes('Nalgonda'));
  assertTrue('public page has NO parent details', !nriHtml.includes('Venkat Rao') && !nriHtml.includes('9822222222'));
  const nriCard = await fetch(`${BASE}/api/profiles/${NPID}/share`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${C}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ method: 'download' }),
  });
  check('download card with the new rows 200', 200, nriCard.status);

  const nriReq = await api('POST', `/api/profiles/${NPID}/contact-request`, C, {});
  await api('POST', `/api/contact-requests/${nriReq.body.contact_request.id}/approve`, A);
  const cGranted = (await api('GET', `/api/profiles/${NPID}`, C)).body.profile;
  check('after approval: native place visible', 'Nalgonda', cGranted.city);
  check('after approval: father phone visible', '9811111111', cGranted.father_phone);
  check('after approval: mother name visible', 'Padma Rao', cGranted.mother_name);
  check('after approval: work place visible', 'San Jose', cGranted.work_place);
  check('after approval: NRI place visible', 'California', cGranted.nri_place);

  const unNri = await api('PATCH', `/api/profiles/${NPID}`, A, { is_nri: false });
  check('PATCH is_nri=false 200', 200, unNri.status);
  check('country cleared when no longer NRI', null, unNri.body.profile.nri_country);
  check('nri=true now excludes it', 0, await hasN('nri=true'));
  check('nri filter still finds by work place', 1, await hasN('city=san'));
  const addCountry = await api('POST', '/api/admin/masters/countries', ADMIN, { name: `Testland ${Date.now()}` });
  check('admin adds a country', 201, addCountry.status);
  check('admin adds a complexion', 201, (await api('POST', '/api/admin/masters/complexions', ADMIN, { name: `Tone ${Date.now()}` })).status);

  // ---------------------------------------------------------------- forgot password
  step('23. Forgot password → admin issues a temporary password → forced change');
  let cPass = 'newpass123'; // changed in step 19
  const forgot = await api('POST', '/api/auth/forgot-password', null, { phone: cPhone });
  check('forgot-password 200', 200, forgot.status);
  check('forgot-password twice is still 200 (no duplicate row)', 200, (await api('POST', '/api/auth/forgot-password', null, { phone: cPhone })).status);
  check('unknown number also 200 (no enumeration)', 200, (await api('POST', '/api/auth/forgot-password', null, { phone: '6000000000' })).status);
  check('bad number 400', 400, (await api('POST', '/api/auth/forgot-password', null, { phone: '12' })).status);
  check('agent blocked from the reset list', 403, (await api('GET', '/api/admin/password-resets', A)).status);
  const resets = await api('GET', '/api/admin/password-resets?status=pending', ADMIN);
  check('admin lists pending resets', 200, resets.status);
  const mine = resets.body.password_resets.filter((r) => r.agent_id === C_ID);
  check('exactly one pending request for C', 1, mine.length);
  check('request shows the agent phone', cPhone, mine[0]?.agent_phone);
  const RESET_ID = mine[0]?.id;
  const adminBadge = await api('GET', '/api/notifications', ADMIN);
  assertTrue('admin notified of the reset', adminBadge.body.counts.pending_password_resets >= 1);
  assertTrue('admin stats count it', (await api('GET', '/api/admin/stats', ADMIN)).body.stats.pending_password_resets >= 1);

  check('temporary password too short 400', 400, (await api('POST', `/api/admin/password-resets/${RESET_ID}/approve`, ADMIN, { temporary_password: '123' })).status);
  const approvedReset = await api('POST', `/api/admin/password-resets/${RESET_ID}/approve`, ADMIN, { temporary_password: 'temp123' });
  check('approve with temporary password 200', 200, approvedReset.status);
  check('agent flagged must_change_password', true, approvedReset.body.agent?.must_change_password);
  check('approving again 409', 409, (await api('POST', `/api/admin/password-resets/${RESET_ID}/approve`, ADMIN, { temporary_password: 'temp123' })).status);
  check('old password no longer works', 401, (await api('POST', '/api/auth/login', null, { phone: cPhone, password: cPass })).status);
  const tempLogin = await api('POST', '/api/auth/login', null, { phone: cPhone, password: 'temp123' });
  check('temporary password logs in', 200, tempLogin.status);
  check('login response says must_change_password', true, tempLogin.body?.agent?.must_change_password);
  const CT = tempLogin.body?.token;
  const gated = await api('GET', '/api/profiles', CT);
  check('data routes blocked until changed', 403, gated.status);
  check('error code password_change_required', 'password_change_required', gated.body?.error);
  check('/auth/me still works', 200, (await api('GET', '/api/auth/me', CT)).status);
  check('re-using the temporary password is refused', 400, (await api('POST', '/api/auth/change-password', CT, { current_password: 'temp123', new_password: 'temp123' })).status);
  cPass = 'fresh12345';
  check('agent sets a new password', 200, (await api('POST', '/api/auth/change-password', CT, { current_password: 'temp123', new_password: cPass })).status);
  check('data routes open again', 200, (await api('GET', '/api/profiles', CT)).status);
  check('flag cleared on /auth/me', false, (await api('GET', '/api/auth/me', CT)).body?.agent?.must_change_password);

  await api('POST', '/api/auth/forgot-password', null, { phone: aPhone });
  const aReset = (await api('GET', '/api/admin/password-resets?status=pending', ADMIN)).body.password_resets.find((r) => r.agent_phone === aPhone);
  assertTrue('A has a pending reset', Boolean(aReset));
  check('admin rejects a reset', 200, (await api('POST', `/api/admin/password-resets/${aReset?.id}/reject`, ADMIN)).status);
  check('rejected agent keeps the old password', 200, (await api('POST', '/api/auth/login', null, { phone: aPhone, password: 'secret123' })).status);
  check('admin cannot reset own password this way', 400, (await api('POST', `/api/admin/agents/${adminLogin.body.agent.id}/reset-password`, ADMIN, { temporary_password: 'temp456' })).status);
  const direct = await api('POST', `/api/admin/agents/${C_ID}/reset-password`, ADMIN, { temporary_password: 'temp456' });
  check('admin resets an agent directly (no request)', 200, direct.status);
  check('direct reset also forces a change', true, direct.body.agent?.must_change_password);
  const CT2 = (await api('POST', '/api/auth/login', null, { phone: cPhone, password: 'temp456' })).body?.token;
  check('leaves the agent gated', 403, (await api('GET', '/api/profiles', CT2)).status);
  check('agent recovers by changing it', 200, (await api('POST', '/api/auth/change-password', CT2, { current_password: 'temp456', new_password: 'final12345' })).status);

  // ---------------------------------------------------------------- birth details + DOB
  step('24. Birth time / birth place, and the DOB shown beside the age');
  const bp = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Birth Details Bride', gender: 'bride', dob: '1997-08-21', height_cm: 158,
    community_id: COMM_A, nakshatram_id: NAK, zodiac_id: ZOD,
    birth_time: '22:40', birth_place: 'Guntur',
    city: 'Nalgonda', state: 'Telangana', contact_phone: '9811111111',
  });
  check('create with birth details 201', 201, bp.status);
  const BP = bp.body?.profile;
  const BPID = BP?.id;
  check('birth_time stored as HH:MM', '22:40', BP?.birth_time);
  check('birth_place stored', 'Guntur', BP?.birth_place);
  check('bad birth time 400', 400, (await api('PATCH', `/api/profiles/${BPID}`, A, { birth_time: '25:99' })).status);
  check('PATCH birth_time 200', 200, (await api('PATCH', `/api/profiles/${BPID}`, A, { birth_time: '04:05' })).status);
  check('empty birth_time clears it', null, (await api('PATCH', `/api/profiles/${BPID}`, A, { birth_time: '' })).body.profile?.birth_time);
  await api('PATCH', `/api/profiles/${BPID}`, A, { birth_time: '22:40' });
  const bpList = (await api('GET', '/api/profiles?q=Birth%20Details', C)).body.profiles.find((x) => x.id === BPID);
  check('list row carries birth_time', '22:40', bpList?.birth_time);
  // Birth place joined the on-request set in 005 (SPEC §9.8).
  check('list row omits birth_place', false, 'birth_place' in (bpList || {}));
  const bpOther = (await api('GET', `/api/profiles/${BPID}`, C)).body.profile;
  check('other agent: birth_place OMITTED', false, 'birth_place' in bpOther);
  check('other agent still sees birth_time', '22:40', bpOther.birth_time);
  const bpShare = await api('POST', `/api/profiles/${BPID}/share`, C, { method: 'whatsapp' });
  const bpText = bpShare.body?.whatsapp_text || '';
  assertTrue('share text shows the DOB beside the age', /\d+ yrs \(21 Aug 1997\)/.test(bpText), bpText);
  assertTrue('share text has NO birth place', !bpText.includes('Guntur'), bpText);
  const bpHtml = await (await fetch(bpShare.body.share_url)).text();
  assertTrue('public page shows the DOB beside the age', bpHtml.includes('years (21 Aug 1997)'));
  assertTrue('public page shows birth time in 12h form', bpHtml.includes('10:40 PM'));
  assertTrue('public page has NO birth place', !bpHtml.includes('Guntur'));
  assertTrue('public page still has NO native place', !bpHtml.includes('Nalgonda'));
  const bpCard = await fetch(`${BASE}/api/profiles/${BPID}/share`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${C}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ method: 'download' }),
  });
  check('download card renders with the birth rows 200', 200, bpCard.status);

  // ---------------------------------------------------------------- hold workflow
  step('25. Hold: any agent asks, uploader/admin approves, the holder keeps seeing it');
  const hp = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Hold Test Groom', gender: 'groom', dob: '1994-05-05', community_id: COMM_A,
  });
  check('hold test profile created', 201, hp.status);
  const HPID = hp.body?.profile?.id;
  const seen = async (token) => (await api('GET', `/api/profiles/${HPID}`, token)).status;
  check('C sees the active profile', 200, await seen(C));

  const hreq = await api('POST', `/api/profiles/${HPID}/hold-request`, C, { note: 'Client is in talks' });
  check('C asks for a hold 201', 201, hreq.status);
  const HR = hreq.body?.hold_request;
  check('request is pending', 'pending', HR?.status);
  check('sent row never carries the uploader', false, 'uploaded_by' in (HR || {}) || 'requester' in (HR || {}));
  check('duplicate hold request 409', 409, (await api('POST', `/api/profiles/${HPID}/hold-request`, C, {})).status);
  check('B (other community) cannot request a hold', 404, (await api('POST', `/api/profiles/${HPID}/hold-request`, B, {})).status);
  check('profile still active while pending', 'active', (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.status);
  check('detail shows my pending hold', 'pending', (await api('GET', `/api/profiles/${HPID}`, C)).body.profile.hold_request_status);
  check('uploader sees the pending count', 1, (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.pending_hold_requests);
  check('requester cannot approve their own hold', 403, (await api('POST', `/api/hold-requests/${HR.id}/approve`, C)).status);
  const aHoldInbox = (await api('GET', '/api/hold-requests?box=inbox', A)).body.hold_requests;
  assertTrue('uploader inbox lists it with the requester', aHoldInbox.some((r) => r.id === HR.id && r.requester?.full_name));
  const cHoldSent = (await api('GET', '/api/hold-requests?box=sent', C)).body.hold_requests;
  assertTrue('sent box lists it without a requester block', cHoldSent.some((r) => r.id === HR.id && !r.requester));
  const aNotif = (await api('GET', '/api/notifications', A)).body;
  check('uploader notifications count the hold', 1, aNotif.counts?.hold_requests_inbox);
  assertTrue('badge includes hold requests', aNotif.badge >= 1);
  assertTrue('notification item for the hold', aNotif.items.some((i) => i.type === 'hold_request_received' && i.id === HR.id));

  check('uploader approves 200', 200, (await api('POST', `/api/hold-requests/${HR.id}/approve`, A)).status);
  check('profile now on_hold', 'on_hold', (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.status);
  check('holder C still sees it', 200, await seen(C));
  check('holder sees hold_request_status approved', 'approved', (await api('GET', `/api/profiles/${HPID}`, C)).body.profile.hold_request_status);
  const dPhone = randomPhone('7');
  const signupD = await signupAgent({
    full_name: 'Agent D', phone: dPhone, password: 'secret123', agency_name: 'D Bureau', community_ids: [COMM_A],
  });
  await api('POST', `/api/admin/agents/${signupD.body?.agent?.id}/activate`, ADMIN);
  const D = signupD.body?.token;
  const D_ID = signupD.body?.agent?.id;
  check('another agent in the community cannot see the held profile', 404, await seen(D));
  check('held profile absent from that agent\'s list', 0, (await api('GET', '/api/profiles?q=Hold%20Test', D)).body.profiles.length);
  check('uploader sees who holds it', C_ID, (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.held_by?.id);
  check('admin sees who holds it', C_ID, (await api('GET', `/api/profiles/${HPID}`, ADMIN)).body.profile.held_by?.id);
  check('holder does NOT get held_by', false, 'held_by' in (await api('GET', `/api/profiles/${HPID}`, C)).body.profile);
  const heldShare = await api('POST', `/api/profiles/${HPID}/share`, C, { method: 'link' });
  check('public link 404s while on hold', 404, (await fetch(heldShare.body.share_url)).status);
  check('outsider cannot release', 403, (await api('POST', `/api/hold-requests/${HR.id}/release`, D)).status);
  check('holder releases 200', 200, (await api('POST', `/api/hold-requests/${HR.id}/release`, C)).status);
  check('profile active again', 'active', (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.status);
  check('the other agent sees it again', 200, await seen(D));
  check('release twice 409', 409, (await api('POST', `/api/hold-requests/${HR.id}/release`, C)).status);

  const own = await api('POST', `/api/profiles/${HPID}/hold-request`, A, {});
  check('uploader\'s own hold is approved at once', 'approved', own.body?.hold_request?.status);
  check('profile on_hold again', 'on_hold', (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.status);
  check('hold on a held profile 409', 409, (await api('POST', `/api/profiles/${HPID}/hold-request`, ADMIN, {})).status);
  await api('PATCH', `/api/profiles/${HPID}`, A, { status: 'active' });
  const ownAfter = (await api('GET', '/api/hold-requests?box=sent', A)).body.hold_requests.find((r) => r.id === own.body.hold_request.id);
  check('PATCH back to active releases the hold', 'released', ownAfter?.status);

  const r2 = await api('POST', `/api/profiles/${HPID}/hold-request`, C, {});
  check('admin rejects 200', 200, (await api('POST', `/api/hold-requests/${r2.body.hold_request.id}/reject`, ADMIN)).status);
  check('profile stays active after a rejection', 'active', (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.status);
  const r3 = await api('POST', `/api/profiles/${HPID}/hold-request`, C, {});
  check('requester cancels 200', 200, (await api('POST', `/api/hold-requests/${r3.body.hold_request.id}/cancel`, C)).status);
  check('cancel twice 409', 409, (await api('POST', `/api/hold-requests/${r3.body.hold_request.id}/cancel`, C)).status);
  const r4 = await api('POST', `/api/profiles/${HPID}/hold-request`, C, {});
  const r5 = await api('POST', `/api/profiles/${HPID}/hold-request`, D, {});
  await api('POST', `/api/hold-requests/${r4.body.hold_request.id}/approve`, A);
  const r5After = (await api('GET', '/api/hold-requests?box=sent', D)).body.hold_requests.find((r) => r.id === r5.body.hold_request.id);
  check('approving one hold turns the other pending one down', 'rejected', r5After?.status);
  await api('POST', `/api/hold-requests/${r4.body.hold_request.id}/release`, A);

  await api('PATCH', `/api/profiles/${HPID}`, A, { status: 'on_hold' });
  const viaPatch = (await api('GET', '/api/hold-requests?box=sent&status=approved', A)).body.hold_requests.filter((r) => r.profile_id === HPID);
  check('PATCH to on_hold logs an approved hold by the uploader', 1, viaPatch.length);
  check('on_hold list filter works for the uploader', 1, (await api('GET', `/api/profiles?mine=true&status=on_hold&q=Hold%20Test`, A)).body.profiles.length);
  const holdStats = (await api('GET', '/api/admin/stats', ADMIN)).body.stats;
  assertTrue('admin stats count holds', typeof holdStats.pending_hold_requests === 'number' && holdStats.on_hold_profiles >= 1);
  await api('PATCH', `/api/profiles/${HPID}`, A, { status: 'active' });

  // ---------------------------------------------------------------- delete
  step('26. Delete: uploader or admin only');
  check('other agent cannot delete', 403, (await api('DELETE', `/api/profiles/${HPID}`, C)).status);
  check('uploader gets can_delete', true, (await api('GET', `/api/profiles/${HPID}`, A)).body.profile.can_delete);
  check('other agent gets can_delete false', false, (await api('GET', `/api/profiles/${HPID}`, C)).body.profile.can_delete);
  check('uploader deletes 200', 200, (await api('DELETE', `/api/profiles/${HPID}`, A)).status);
  check('deleted profile 404', 404, (await api('GET', `/api/profiles/${HPID}`, A)).status);
  check('admin deletes another agent\'s profile', 200, (await api('DELETE', `/api/profiles/${BPID}`, ADMIN)).status);
  check('deleting again 404', 404, (await api('DELETE', `/api/profiles/${BPID}`, ADMIN)).status);
  check('its share link is gone too', 404, (await fetch(bpShare.body.share_url)).status);


  // ---------------------------------------------------------------- Mediator fields + PDF share
  step('27. Religion, mother tongue, known languages, food habit, siblings — and the PDF share');
  const REL = m.religions[0].id;
  const LANG = m.languages.slice(0, 3).map((l) => l.id);
  const FOOD = m.food_habits[0].id;
  const mf = await apiForm(
    'POST',
    '/api/profiles',
    A,
    {
      full_name: 'Mediator Fields Bride', gender: 'bride', dob: '1996-03-03', height_cm: 158, community_id: COMM_A,
      religion_id: REL, mother_tongue_id: LANG[0], known_language_ids: LANG.join(','), food_habit_id: FOOD,
      has_siblings: 'true', siblings_count: 2,
      siblings_details: 'One elder brother (married, Pune), one younger sister.',
      city: 'Nalgonda', state: 'Telangana', contact_phone: '9811111111', about: 'Calm and cheerful.',
    },
    [{ buffer: TINY_JPEG, name: 'photo.jpg', type: 'image/jpeg' }],
  );
  check('create with the new fields 201', 201, mf.status);
  const MF = mf.body?.profile;
  const MFID = MF?.id;
  check('religion resolved', m.religions[0].name, MF?.religion?.name);
  check('mother tongue resolved', m.languages[0].name, MF?.mother_tongue?.name);
  check('known languages saved (3)', 3, MF?.known_languages?.length);
  check('food habit resolved', m.food_habits[0].name, MF?.food_habit?.name);
  check('has_siblings true', true, MF?.has_siblings);
  check('siblings_count 2', 2, MF?.siblings_count);
  assertTrue('siblings_details saved', (MF?.siblings_details || '').includes('elder brother'));

  const mfList = (
    await api('GET', `/api/profiles?religion_id=${REL}&language_id=${LANG[1]}&food_habit_id=${FOOD}`, C)
  ).body.profiles;
  assertTrue('list filters by religion + language + food habit', mfList.some((x) => x.id === MFID));
  const mfRow = mfList.find((x) => x.id === MFID);
  check('list row carries known languages', 3, mfRow?.known_languages?.length);
  // Siblings joined the on-request set in 005 (SPEC §9.8).
  check('list row omits has_siblings', false, 'has_siblings' in (mfRow || {}));
  check('list row omits siblings_count', false, 'siblings_count' in (mfRow || {}));
  const mfOther = (await api('GET', `/api/profiles/${MFID}`, C)).body.profile;
  check('other agent: has_siblings OMITTED', false, 'has_siblings' in mfOther);
  check('other agent: siblings_details OMITTED', false, 'siblings_details' in mfOther);
  check('other agent: family_details OMITTED', false, 'family_details' in mfOther);
  check('other agent still sees food habit', m.food_habits[0].name, mfOther.food_habit?.name);
  check('unknown language 400', 400, (await api('PATCH', `/api/profiles/${MFID}`, A, { known_language_ids: [999999] })).status);
  const mfClear = await api('PATCH', `/api/profiles/${MFID}`, A, { known_language_ids: [] });
  check('PATCH clears known languages', 0, mfClear.body.profile?.known_languages?.length);
  const mfNone = await api('PATCH', `/api/profiles/${MFID}`, A, { has_siblings: false });
  check('no siblings -> count 0', 0, mfNone.body.profile?.siblings_count);
  check('no siblings -> details null', null, mfNone.body.profile?.siblings_details);
  const mfUnset = await api('PATCH', `/api/profiles/${MFID}`, A, { has_siblings: null });
  check('siblings not recorded -> null', null, mfUnset.body.profile?.has_siblings);
  await api('PATCH', `/api/profiles/${MFID}`, A, {
    has_siblings: true, siblings_count: 2,
    siblings_details: 'One elder brother (married, Pune), one younger sister.', known_language_ids: LANG,
  });

  const mfShare = await api('POST', `/api/profiles/${MFID}/share`, C, { method: 'whatsapp' });
  check('share 200', 200, mfShare.status);
  assertTrue('share text mentions religion', (mfShare.body.whatsapp_text || '').includes(m.religions[0].name));
  const mfHtml = await (await fetch(mfShare.body.share_url)).text();
  assertTrue('public page shows religion', mfHtml.includes(m.religions[0].name));
  assertTrue('public page shows mother tongue', mfHtml.includes('Mother tongue'));
  assertTrue('public page shows languages known', mfHtml.includes('Languages known'));
  assertTrue('public page has NO siblings row at all', !/Siblings<\/dt>/.test(mfHtml));
  assertTrue('public page has NO siblings details', !mfHtml.includes('elder brother'));
  assertTrue('share text has NO siblings details', !(mfShare.body.whatsapp_text || '').includes('elder brother'));
  assertTrue('public page still has NO native place', !mfHtml.includes('Nalgonda'));
  assertTrue('public page is branded Mediator', mfHtml.includes('Mediator'));
  assertTrue('public page has an og:image for WhatsApp previews', mfHtml.includes('og:image'));

  const pdfRes = await fetch(`${BASE}/api/profiles/${MFID}/share`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${C}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ method: 'pdf' }),
  });
  const pdfBuf = Buffer.from(await pdfRes.arrayBuffer());
  check('PDF share 200', 200, pdfRes.status);
  check('PDF content type', 'application/pdf', pdfRes.headers.get('content-type'));
  assertTrue(`PDF starts with %PDF (${pdfBuf.length} bytes)`, pdfBuf.subarray(0, 4).toString() === '%PDF');
  assertTrue('PDF is not empty', pdfBuf.length > 10000, `${pdfBuf.length} bytes`);
  assertTrue(
    'PDF filename is set',
    /filename=".*\.pdf"/.test(pdfRes.headers.get('content-disposition') || ''),
  );
  check('unknown share method 400', 400, (await api('POST', `/api/profiles/${MFID}/share`, C, { method: 'fax' })).status);
  const mfLogs = (await api('GET', `/api/admin/logs/shares?profile_id=${MFID}`, ADMIN)).body.logs;
  assertTrue('pdf share was logged', mfLogs.some((l) => l.method === 'pdf'));
  check('agent outside the community cannot fetch a PDF (404)', 404, (await api('POST', `/api/profiles/${MFID}/share`, B, { method: 'pdf' })).status);

  // ================================================================ SPEC §9 — Gandharva
  // ---------------------------------------------------------------- OTP hardening
  step('28. OTP hardening (SPEC §9.1): cooldown, wrong / consumed codes, proof of the number');
  const xPhone = randomPhone('9');
  const xSend = await api('POST', '/api/auth/otp/send', null, { phone: xPhone });
  check('otp send 200', 200, xSend.status);
  check('send response says sent', true, xSend.body?.sent);
  check('send response carries expires_in 300', 300, xSend.body?.expires_in);
  check('send response carries retry_after 30', 30, xSend.body?.retry_after);
  if (xSend.body?.mock) {
    assertTrue('mock provider echoes a 6-digit mock_code', /^\d{6}$/.test(String(xSend.body?.mock_code ?? OTP_CODE)));
  } else {
    console.log('  (real OTP provider — using OTP_CODE for the verifications)');
  }
  const xCode = codeFrom(xSend);
  const wrongCode = xCode === '000000' ? '999999' : '000000';
  const cooldown = await api('POST', '/api/auth/otp/send', null, { phone: xPhone });
  check('resend within 30 s is 429', 429, cooldown.status);
  check('error code otp_cooldown', 'otp_cooldown', cooldown.body?.error);
  const wrong = await api('POST', '/api/auth/otp/verify', null, { phone: xPhone, code: wrongCode });
  check('wrong code 400', 400, wrong.status);
  check('error code invalid_otp', 'invalid_otp', wrong.body?.error);
  check('non-numeric code is a validation error', 400, (await api('POST', '/api/auth/otp/verify', null, { phone: xPhone, code: 'abc' })).status);
  const noProof = await api('POST', '/api/auth/signup', null, {
    full_name: 'Agent X', phone: xPhone, password: 'secret123', agency_name: 'X Bureau', community_ids: [COMM_A],
  });
  check('signup without a verification token 400', 400, noProof.status);
  check('error code phone_not_verified', 'phone_not_verified', noProof.body?.error);
  check('garbage token is phone_not_verified too', 'phone_not_verified', (await api('POST', '/api/auth/signup', null, {
    full_name: 'Agent X', phone: xPhone, password: 'secret123', community_ids: [COMM_A], phone_verification_token: 'nope.nope.nope',
  })).body?.error);
  const xVerify = await api('POST', '/api/auth/otp/verify', null, { phone: xPhone, code: xCode });
  check('right code 200', 200, xVerify.status);
  const X_TOKEN = xVerify.body?.verification_token;
  assertTrue('verify returns a verification_token', typeof X_TOKEN === 'string' && X_TOKEN.split('.').length === 3);
  const consumed = await api('POST', '/api/auth/otp/verify', null, { phone: xPhone, code: xCode });
  check('a code verifies once — second use 410', 410, consumed.status);
  check('error code otp_expired', 'otp_expired', consumed.body?.error);
  const otherPhone = await api('POST', '/api/auth/signup', null, {
    full_name: 'Agent Y', phone: randomPhone('8'), password: 'secret123', community_ids: [COMM_A], phone_verification_token: X_TOKEN,
  });
  check('token for another number is refused', 400, otherPhone.status);
  check('error code phone_not_verified', 'phone_not_verified', otherPhone.body?.error);
  const signupX = await api('POST', '/api/auth/signup', null, {
    full_name: 'Agent X', phone: xPhone, password: 'secret123', agency_name: 'X Bureau', community_ids: [COMM_A], phone_verification_token: X_TOKEN,
  });
  check('signup with the proof 201', 201, signupX.status);
  check('agent X is pending (rule 2)', 'pending', signupX.body?.agent?.status);
  const X_ID = signupX.body?.agent?.id; // stays pending: the "inactive agent" fixture below
  check('same proof again 409 phone_taken', 409, (await api('POST', '/api/auth/signup', null, {
    full_name: 'Agent X', phone: xPhone, password: 'secret123', community_ids: [COMM_A], phone_verification_token: X_TOKEN,
  })).status);
  check('otp send for a number that is now an agent 409', 409, (await api('POST', '/api/auth/otp/send', null, { phone: xPhone })).status);
  check('otp send with a bad number 400', 400, (await api('POST', '/api/auth/otp/send', null, { phone: '12' })).status);

  // Customer side: any number may ask for a code (no enumeration); verify says login vs new.
  const kPhone = randomPhone('6');
  const kSend = await api('POST', '/api/customer/auth/otp/send', null, { phone: kPhone });
  check('customer otp send 200 for an unknown number', 200, kSend.status);
  const kCode = codeFrom(kSend);
  check('customer wrong code 400', 400, (await api('POST', '/api/customer/auth/otp/verify', null, { phone: kPhone, code: xCode === kCode ? wrongCode : '000000' })).status);
  const kVerify = await api('POST', '/api/customer/auth/otp/verify', null, { phone: kPhone, code: kCode });
  check('customer verify 200', 200, kVerify.status);
  check('unknown number → new: true', true, kVerify.body?.new);
  const K_TOKEN = kVerify.body?.verification_token;
  assertTrue('… with a verification_token', typeof K_TOKEN === 'string');
  check('customer verify twice 410', 410, (await api('POST', '/api/customer/auth/otp/verify', null, { phone: kPhone, code: kCode })).status);
  const kNoProof = await api('POST', '/api/customer/auth/signup', null, { full_name: 'Kiran Customer', phone: kPhone, agent_phone: cPhone });
  check('customer signup without proof 400', 400, kNoProof.status);
  check('error code phone_not_verified', 'phone_not_verified', kNoProof.body?.error);
  check('agent-purpose token is not customer proof', 'phone_not_verified', (await api('POST', '/api/customer/auth/signup', null, {
    full_name: 'Kiran Customer', phone: kPhone, agent_phone: cPhone, phone_verification_token: X_TOKEN,
  })).body?.error);
  const noAgent = await api('POST', '/api/customer/auth/signup', null, {
    full_name: 'Kiran Customer', phone: kPhone, agent_phone: '6000000001', phone_verification_token: K_TOKEN,
  });
  check('unknown agent phone 404', 404, noAgent.status);
  check('error code agent_not_found', 'agent_not_found', noAgent.body?.error);
  const pendingAgent = await api('POST', '/api/customer/auth/signup', null, {
    full_name: 'Kiran Customer', phone: kPhone, agent_phone: xPhone, phone_verification_token: K_TOKEN,
  });
  check('pending agent 400', 400, pendingAgent.status);
  check('error code agent_not_active', 'agent_not_active', pendingAgent.body?.error);

  // ---------------------------------------------------------------- customer signup + pending gating
  step('29. Customer signup is PENDING until the agent approves (SPEC §9.2 / §9.3-A / §9.9)');
  const signupK = await api('POST', '/api/customer/auth/signup', null, {
    full_name: 'Kiran Customer', phone: kPhone, agent_phone: `+91 ${cPhone}`, phone_verification_token: K_TOKEN,
  });
  check('customer signup 201', 201, signupK.status);
  const K1 = signupK.body?.token;
  const K1_ID = signupK.body?.customer?.id;
  check('new customer is pending', 'pending', signupK.body?.customer?.status);
  check('source is app', 'app', signupK.body?.customer?.source);
  check('attached to agent C', C_ID, signupK.body?.customer?.agent?.id);
  check('me carries the agent as a directory card (phone)', cPhone, signupK.body?.customer?.agent?.phone);
  check("me carries the agent's communities (C is in 2)", 2, signupK.body?.customer?.agent?.communities?.length);
  check('no profile yet', false, signupK.body?.customer?.has_profile);
  check('no pending agent change', null, signupK.body?.customer?.pending_agent_change);
  check('same number again 409 phone_taken', 409, (await api('POST', '/api/customer/auth/signup', null, {
    full_name: 'Kiran Customer', phone: kPhone, agent_phone: cPhone, phone_verification_token: K_TOKEN,
  })).status);
  if (!K1) {
    console.log(red('\nCannot continue without a customer token.'));
    process.exit(1);
  }

  // Two audiences, one JWT secret: the typ claim keeps them apart (SPEC §9.2).
  const kOnAgent = await api('GET', '/api/profiles', K1);
  check('customer token on an agent route 401', 401, kOnAgent.status);
  check('error code invalid_token', 'invalid_token', kOnAgent.body?.error);
  check('customer token on /clients 401', 401, (await api('GET', '/api/clients', K1)).status);
  check('customer token on /auth/me 401', 401, (await api('GET', '/api/auth/me', K1)).status);
  const cOnCustomer = await api('GET', '/api/customer/auth/me', C);
  check('agent token on a customer route 401', 401, cOnCustomer.status);
  check('error code invalid_token', 'invalid_token', cOnCustomer.body?.error);
  check('agent token on /customer/profiles 401', 401, (await api('GET', '/api/customer/profiles', C)).status);
  check('no token on a customer route 401', 401, (await api('GET', '/api/customer/profile')).status);

  const kMe = await api('GET', '/api/customer/auth/me', K1);
  check('pending customer CAN read /customer/auth/me (waiting screen)', 200, kMe.status);
  check('me says pending', 'pending', kMe.body?.customer?.status);
  // v2.2 (SPEC §9.12): a pending customer browses in GUEST mode — locked cards only.
  const kBrowse = await api('GET', '/api/customer/profiles', K1);
  check('pending customer browses as a guest 200', 200, kBrowse.status);
  check('browse says access guest', 'guest', kBrowse.body?.access);
  check('guest rows are locked', true, kBrowse.body?.profiles?.every((x) => x.locked === true));
  check('guest rows carry no name', true, kBrowse.body?.profiles?.every((x) => !('full_name' in x)));
  check('pending customer cannot open a profile', 'unlock_required', (await api('GET', `/api/customer/profiles/${PID}`, K1)).body?.error);
  check('pending customer cannot list interests', 403, (await api('GET', '/api/customer/interests', K1)).status);
  check('pending customer CAN see the agent directory (guest mode)', 200, (await api('GET', '/api/customer/agents', K1)).status);
  check('pending customer cannot ask to change agent', 403, (await api('POST', '/api/customer/agent-change', K1, { to_agent_id: B_ID })).status);
  check('pending customer cannot mark interest', 403, (await api('POST', `/api/customer/profiles/${PID}/interest`, K1, {})).status);
  const noProfile = await api('GET', '/api/customer/profile', K1);
  check('own profile before creating it 404', 404, noProfile.status);
  check('error code no_profile', 'no_profile', noProfile.body?.error);

  // The profile can be filled in while waiting; it is stored HIDDEN and `status` is ignored.
  const kCreate = await apiForm('POST', '/api/customer/profile', K1, {
    full_name: 'Kiran Customer', gender: 'groom', dob: '1995-09-09', height_cm: 172, community_id: COMM_A,
    education_id: EDU, profession_id: PROF, status: 'active', about: 'Software engineer, likes trekking.',
    city: 'Nalgonda', state: 'Telangana', father_name: 'Krishna Rao', father_phone: '9833333333',
    contact_name: 'Krishna Rao', contact_phone: '9833333333', work_place: 'Hyderabad',
    has_siblings: 'true', siblings_count: 1, elder_sisters: 1, family_details: 'Father runs a shop.',
  }, [{ buffer: TINY_JPEG, name: 'me.jpg', type: 'image/jpeg' }]);
  check('pending customer creates their profile 201', 201, kCreate.status);
  const KP = kCreate.body?.profile;
  const K1PID = KP?.id;
  check('profile stored hidden while pending', 'hidden', KP?.status);
  check('profile is mine', true, KP?.is_mine);
  check('profile flagged as a customer profile', true, KP?.is_customer_profile);
  check('owner sees the on-request block (native place)', 'Nalgonda', KP?.city);
  check('owner sees father phone', '9833333333', KP?.father_phone);
  check('owner sees siblings', 1, KP?.elder_sisters);
  check('owner contact_access granted', 'granted', KP?.contact_access);
  check('photo stored', 1, KP?.photos?.length);
  assertTrue('photo url points at the customer photo route', String(KP?.photos?.[0]?.url || '').startsWith('/api/customer/photos/'));
  check('uploader identity never sent to a customer', false, 'uploaded_by' in (KP || {}));
  const kAgain = await apiForm('POST', '/api/customer/profile', K1, { full_name: 'Dup', gender: 'groom', dob: '1995-09-09', community_id: COMM_A });
  check('second profile 409', 409, kAgain.status);
  check('error code profile_exists', 'profile_exists', kAgain.body?.error);
  check('GET own profile 200', 200, (await api('GET', '/api/customer/profile', K1)).status);
  const kPatch = await api('PATCH', '/api/customer/profile', K1, { status: 'active', about: 'Updated while pending.' });
  check('PATCH own profile 200', 200, kPatch.status);
  check('PATCH ignores status (still hidden)', 'hidden', kPatch.body?.profile?.status);
  check('PATCH applied the other field', 'Updated while pending.', kPatch.body?.profile?.about);
  check('empty PATCH 400', 400, (await api('PATCH', '/api/customer/profile', K1, { status: 'active' })).status);
  const ownPhoto = await raw(`${BASE}${KP.photos[0].url}`, { token: K1 });
  check('own photo streams while pending', 200, ownPhoto.status);
  check('own photo is a JPEG', 'image/jpeg', ownPhoto.headers.get('content-type'));
  const kMore = await apiForm('POST', '/api/customer/profile/photos', K1, {}, [{ buffer: TINY_JPEG, name: 'two.jpg', type: 'image/jpeg' }]);
  check('add a photo 201', 201, kMore.status);
  const K1_PHOTO2 = kMore.body?.photos?.[0]?.id;
  check('make it primary 200', 200, (await api('POST', `/api/customer/photos/${K1_PHOTO2}/primary`, K1)).status);
  check('delete it 200', 200, (await api('DELETE', `/api/customer/photos/${K1_PHOTO2}`, K1)).status);
  check('cannot delete another profile\'s photo', 403, (await api('DELETE', `/api/customer/photos/${P.photos[0].id}`, K1)).status);
  check('guest gets the primary photo of an active profile', 200, (await raw(`${BASE}/api/customer/photos/${P.photos[0].id}`, { token: K1 })).status);
  check('me now has a profile', true, (await api('GET', '/api/customer/auth/me', K1)).body?.customer?.has_profile);
  check('the new profile is unpaid', 'payment_pending', (await api('GET', '/api/customer/profile', K1)).body?.profile?.visibility);
  // Pay the ₹150 fee (mock) while pending — it stays hidden until approval (SPEC §9.12).
  const kOrder = await api('POST', `/api/customer/my-profiles/${K1PID}/payment`, K1);
  check('checkout 201', 201, kOrder.status);
  const kPaid = await api('POST', `/api/customer/payments/${kOrder.body?.payment?.id}/confirm`, K1, {});
  check('mock payment confirmed', 'paid', kPaid.body?.payment?.status);
  check('paid while pending → awaiting approval', 'awaiting_approval', kPaid.body?.profile?.visibility);
  check('… and still hidden', 'hidden', kPaid.body?.profile?.status);

  // The hidden profile belongs to the customer's agent (uploaded_by = C) and stays invisible to others.
  const cSeesK = await api('GET', `/api/profiles/${K1PID}`, C);
  check('agent C sees the hidden profile under their uploads', 200, cSeesK.status);
  check('uploaded_by is the agent', C_ID, cSeesK.body?.profile?.uploaded_by);
  check('agent sees which customer owns it', K1_ID, cSeesK.body?.profile?.customer_id);
  check('hidden customer profile invisible to agent A', 404, (await api('GET', `/api/profiles/${K1PID}`, A)).status);
  check('C lists it under mine + hidden', 1, (await api('GET', `/api/profiles?mine=true&status=hidden&q=Kiran%20Customer`, C)).body?.profiles?.filter((x) => x.id === K1PID).length);

  // ---------------------------------------------------------------- agent: Clients
  step('30. Clients (SPEC §9.5): own clients only, approve flips the hidden profile, registration link');
  const cClients = await api('GET', '/api/clients', C);
  check('clients list 200', 200, cClients.status);
  const kRow = cClients.body?.clients?.find((x) => x.id === K1_ID);
  assertTrue('K1 appears in C\'s clients', Boolean(kRow));
  check('client row is pending', 'pending', kRow?.status);
  check('client row source app', 'app', kRow?.source);
  check('client row phone (own agent sees it)', kPhone, kRow?.phone);
  check('client row embeds the profile summary', K1PID, kRow?.profile?.id);
  check('embedded profile is hidden', 'hidden', kRow?.profile?.status);
  check('has_profile true', true, kRow?.has_profile);
  check('interests_count 0', 0, kRow?.interests_count);
  check('no pending agent change', null, kRow?.pending_agent_change);
  check('agent rows do not carry `agent` (admin only)', false, 'agent' in (kRow || {}));
  check('status filter finds it', 1, (await api('GET', '/api/clients?status=pending', C)).body?.clients?.filter((x) => x.id === K1_ID).length);
  check('q filter by phone finds it', 1, (await api('GET', `/api/clients?q=${kPhone}`, C)).body?.clients?.filter((x) => x.id === K1_ID).length);
  check('another agent does not list it', 0, (await api('GET', '/api/clients', A)).body?.clients?.filter((x) => x.id === K1_ID).length);
  const aDetail = await api('GET', `/api/clients/${K1_ID}`, A);
  check('another agent cannot open it', 403, aDetail.status);
  check('error code not_your_client', 'not_your_client', aDetail.body?.error);
  check('another agent cannot approve it', 403, (await api('POST', `/api/clients/${K1_ID}/approve`, A)).status);
  check('unknown client 404', 404, (await api('GET', '/api/clients/999999999', C)).status);
  const cDetail = await api('GET', `/api/clients/${K1_ID}`, C);
  check('own client detail 200', 200, cDetail.status);
  check('detail embeds interests[]', 0, cDetail.body?.client?.interests?.length);
  check('detail embeds agent_change_requests[]', 0, cDetail.body?.client?.agent_change_requests?.length);
  const cNotif = (await api('GET', '/api/notifications', C)).body;
  assertTrue('agent is notified of the pending client', cNotif?.counts?.pending_clients >= 1);
  assertTrue('notification item client_pending', cNotif?.items?.some((i) => i.type === 'client_pending' && i.customer_id === K1_ID));
  assertTrue('badge includes pending clients', cNotif?.badge >= 1);

  const approved1 = await api('POST', `/api/clients/${K1_ID}/approve`, C);
  check('approve 200', 200, approved1.status);
  check('client now active', 'active', approved1.body?.client?.status);
  assertTrue('approved_at stamped', Boolean(approved1.body?.client?.approved_at));
  check('the hidden profile went active with them', 'active', approved1.body?.client?.profile?.status);
  check('approve twice 409', 409, (await api('POST', `/api/clients/${K1_ID}/approve`, C)).status);
  check('error code wrong_status', 'wrong_status', (await api('POST', `/api/clients/${K1_ID}/approve`, C)).body?.error);
  check('reject an active client 409', 409, (await api('POST', `/api/clients/${K1_ID}/reject`, C)).status);
  check('customer sees active on /me', 'active', (await api('GET', '/api/customer/auth/me', K1)).body?.customer?.status);
  check('customer\'s own profile reads active', 'active', (await api('GET', '/api/customer/profile', K1)).body?.profile?.status);
  const aSeesK = await api('GET', `/api/profiles/${K1PID}`, A);
  check('agent A (same community) now sees the profile', 200, aSeesK.status);
  check('… without uploader identity', false, 'uploaded_by' in (aSeesK.body?.profile || {}));
  check('… without the owning customer', false, 'customer_id' in (aSeesK.body?.profile || {}));
  check('… without the on-request block', false, 'father_phone' in (aSeesK.body?.profile || {}));
  check('… flagged as a customer profile', true, aSeesK.body?.profile?.is_customer_profile);
  check('suspend 200', 200, (await api('POST', `/api/clients/${K1_ID}/suspend`, C)).status);
  const kSuspended = await api('GET', '/api/customer/profiles', K1);
  check('suspended customer blocked', 403, kSuspended.status);
  check('error code account_suspended', 'account_suspended', kSuspended.body?.error);
  check('activate 200', 200, (await api('POST', `/api/clients/${K1_ID}/activate`, C)).status);
  check('activate an active client 409', 409, (await api('POST', `/api/clients/${K1_ID}/activate`, C)).status);

  // Reject path with a second app customer.
  const k2Phone = randomPhone('6');
  const signupK2 = await signupCustomer({ full_name: 'Reject Me', phone: k2Phone, agent_phone: cPhone });
  check('second customer signup 201', 201, signupK2.status);
  const K2 = signupK2.body?.token;
  const K2_ID = signupK2.body?.customer?.id;
  check('admin can open any client', 200, (await api('GET', `/api/clients/${K2_ID}`, ADMIN)).status);
  check('admin client rows carry the owning agent', C_ID, (await api('GET', `/api/clients/${K2_ID}`, ADMIN)).body?.client?.agent?.id);
  const rejected = await api('POST', `/api/clients/${K2_ID}/reject`, C);
  check('reject 200', 200, rejected.status);
  check('client now rejected', 'rejected', rejected.body?.client?.status);
  check('approve a rejected client (agent) 409', 409, (await api('POST', `/api/clients/${K2_ID}/approve`, C)).status);
  const k2Blocked = await api('GET', `/api/customer/profiles/${PID}`, K2);
  check('rejected customer cannot open profiles', 403, k2Blocked.status);
  check('error code unlock_required', 'unlock_required', k2Blocked.body?.error);
  check('rejected customer still reads /me', 'rejected', (await api('GET', '/api/customer/auth/me', K2)).body?.customer?.status);

  // Registration link (SPEC §9.3-B).
  const link1 = await api('GET', '/api/clients/registration-link', C);
  check('registration link 200', 200, link1.status);
  assertTrue('link looks like /r/<token>', /\/r\/[A-Za-z0-9_-]{8,64}$/.test(link1.body?.url || ''), link1.body?.url);
  assertTrue('whatsapp text carries the link and the agent', (link1.body?.whatsapp_text || '').includes(link1.body?.url) && (link1.body?.whatsapp_text || '').includes('Agent C'));
  check('same link on a second read', link1.body?.url, (await api('GET', '/api/clients/registration-link', C)).body?.url);
  check('the form is public', 200, (await raw(link1.body.url)).status);
  const link2 = await api('POST', '/api/clients/registration-link/rotate', C);
  check('rotate 200', 200, link2.status);
  assertTrue('rotate changes the link', link2.body?.url && link2.body.url !== link1.body?.url);
  check('old link 404s', 404, (await raw(link1.body.url)).status);
  check('new link works', 200, (await raw(link2.body.url)).status);
  const REG_URL = link2.body?.url;
  const OLD_REG_URL = link1.body?.url;

  // ---------------------------------------------------------------- customer browse scope
  step('31. Customer browse (SPEC §9.9): opposite gender, agent\'s communities, never self, never on-request');
  // K1 is a groom in community A, attached to C (communities A + B after step 15).
  let COMM_X = m.communities[2]?.id;
  if (!COMM_X) {
    const addX = await api('POST', '/api/admin/masters/communities', ADMIN, { name: `Scope Community ${Date.now()}` });
    COMM_X = addX.body?.row?.id;
  }
  assertTrue('a third community exists for the out-of-scope fixture', Boolean(COMM_X));
  const scopePhoto = await samplePhoto('Scope');
  const scopeBride = await apiForm('POST', '/api/profiles', B, {
    full_name: 'Scope Test Bride', gender: 'bride', dob: '1997-01-15', height_cm: 160, community_id: COMM_B,
    city: 'Ongole', state: 'Andhra Pradesh', father_name: 'Bride Father', contact_phone: '9844444444',
    work_place: 'Vijayawada', family_details: 'Two brothers, both married.', has_siblings: 'true', siblings_count: 2,
  }, [{ buffer: scopePhoto, name: 'scope.jpg', type: 'image/jpeg' }]);
  check('B uploads a bride in community B', 201, scopeBride.status);
  const SBID = scopeBride.body?.profile?.id;
  const SB_PHOTO = scopeBride.body?.profile?.photos?.[0]?.id;
  const scopeGroom = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Scope Test Groom', gender: 'groom', dob: '1993-01-15', community_id: COMM_A,
  });
  check('A uploads a groom in community A', 201, scopeGroom.status);
  const SGID = scopeGroom.body?.profile?.id;
  const outside = await apiForm('POST', '/api/profiles', ADMIN, {
    full_name: 'Scope Outside Bride', gender: 'bride', dob: '1998-01-15', community_id: COMM_X,
  }, [{ buffer: TINY_JPEG, name: 'o.jpg', type: 'image/jpeg' }]);
  check('admin uploads a bride outside C\'s communities', 201, outside.status);
  const OBID = outside.body?.profile?.id;
  const OB_PHOTO = outside.body?.profile?.photos?.[0]?.id;

  const browse = await api('GET', '/api/customer/profiles?limit=100', K1);
  check('browse 200', 200, browse.status);
  check('gender defaults to the opposite of my profile (bride)', 'bride', browse.body?.gender);
  assertTrue('every row is a bride', (browse.body?.profiles || []).every((x) => x.gender === 'bride'));
  assertTrue('every row is active', (browse.body?.profiles || []).every((x) => x.status === 'active'));
  assertTrue('every row is in one of the agent\'s communities', (browse.body?.profiles || []).every((x) => [COMM_A, COMM_B].includes(x.community?.id)));
  const seesInBrowse = async (qs, id, token = K1) =>
    ((await api('GET', `/api/customer/profiles?${qs}`, token)).body?.profiles || []).filter((x) => x.id === id).length;
  check('sees Priya (community A, uploaded by A)', 1, await seesInBrowse('q=Priya%20Kumari&limit=100', PID));
  check('sees the bride in community B (agent C is in B too)', 1, await seesInBrowse('q=Scope%20Test%20Bride', SBID));
  check('bride outside the agent\'s communities is NOT listed', 0, await seesInBrowse('q=Scope%20Outside', OBID));
  check('grooms are not listed by default', 0, await seesInBrowse('q=Scope%20Test%20Groom', SGID));
  check('gender=groom overrides the default', 1, await seesInBrowse('gender=groom&q=Scope%20Test%20Groom', SGID));
  check('own profile is never listed', 0, await seesInBrowse('gender=groom&q=Kiran%20Customer', K1PID));
  check('community filter narrows within scope', 0, await seesInBrowse(`community_id=${COMM_A}&q=Scope%20Test%20Bride`, SBID));
  // `mine` / `status` are not customer filters (SPEC §9.9): they are ignored, never honoured.
  check('mine=true is ignored (own profile still absent)', 0, await seesInBrowse('mine=true&gender=groom&q=Kiran%20Customer', K1PID));
  const kRowP = (await api('GET', `/api/customer/profiles?q=Priya%20Kumari&limit=100`, K1)).body.profiles.find((x) => x.id === PID);
  for (const key of ['city', 'state', 'work_place', 'birth_place', 'father_name', 'contact_phone', 'family_details', 'has_siblings', 'siblings_count', 'uploaded_by', 'customer_id']) {
    check(`browse row omits ${key}`, false, key in (kRowP || {}));
  }
  check('browse row carries interest_status null', null, kRowP?.interest_status);
  check('browse row carries is_interested false', false, kRowP?.is_interested);
  check('browse row is_mine false', false, kRowP?.is_mine);
  assertTrue('browse row photo urls use the customer photo route', String(kRowP?.primary_photo_url || '').startsWith('/api/customer/photos/'));

  const kDetail = await api('GET', `/api/customer/profiles/${PID}`, K1);
  check('customer detail 200', 200, kDetail.status);
  check('detail contact_access none', 'none', kDetail.body?.profile?.contact_access);
  check('detail interest null', null, kDetail.body?.profile?.interest);
  for (const key of ['city', 'contact_phone', 'father_phone', 'work_place', 'family_details', 'siblings_details', 'property_share', 'uploaded_by', 'customer_id']) {
    check(`customer detail omits ${key}`, false, key in (kDetail.body?.profile || {}));
  }
  check('detail still shows public horoscope (birth_time)', true, 'birth_time' in (kDetail.body?.profile || {}));
  check('out-of-scope profile detail 404', 404, (await api('GET', `/api/customer/profiles/${OBID}`, K1)).status);
  await api('PATCH', `/api/profiles/${SGID}`, A, { status: 'hidden' });
  check('hidden profile detail 404 for a customer', 404, (await api('GET', `/api/customer/profiles/${SGID}`, K1)).status);
  check('hidden profile absent from the customer list', 0, await seesInBrowse('gender=groom&q=Scope%20Test%20Groom', SGID));
  check('status=hidden is ignored (still absent)', 0, await seesInBrowse('status=hidden&gender=groom&q=Scope%20Test%20Groom', SGID));
  await api('PATCH', `/api/profiles/${SGID}`, A, { status: 'active' });
  const kOwnDetail = await api('GET', `/api/customer/profiles/${K1PID}`, K1);
  check('own profile through the browse route 200', 200, kOwnDetail.status);
  check('own profile carries the on-request block', 'Nalgonda', kOwnDetail.body?.profile?.city);
  check('own profile is_mine', true, kOwnDetail.body?.profile?.is_mine);

  // Other people's photos are WATERMARKED for customers; the agent's copy is not.
  const plain = await raw(`${BASE}/api/photos/${SB_PHOTO}`, { token: B });
  const marked = await raw(`${BASE}/api/customer/photos/${SB_PHOTO}`, { token: K1 });
  check('customer fetches another profile\'s photo 200', 200, marked.status);
  check('… as a JPEG', 'image/jpeg', marked.headers.get('content-type'));
  assertTrue('… and it is a JPEG', marked.buffer[0] === 0xff && marked.buffer[1] === 0xd8);
  assertTrue('… watermarked (differs from the agent\'s plain copy)', plain.status === 200 && !plain.buffer.equals(marked.buffer),
    `plain ${plain.buffer.length} bytes vs customer ${marked.buffer.length} bytes`);
  check('photo of an out-of-scope profile 404', 404, (await raw(`${BASE}/api/customer/photos/${OB_PHOTO}`, { token: K1 })).status);
  check('unknown photo 404', 404, (await raw(`${BASE}/api/customer/photos/999999999`, { token: K1 })).status);

  // ---------------------------------------------------------------- interests
  step('32. Interests (SPEC §9.4): mark → both agents see each other → accept unlocks for 15 days → revoke / decline / withdraw');
  const A_ID = aRow.id;
  // K1's profile is in community A. B (community B only) cannot see it yet…
  check('B cannot see the customer\'s profile before any interest', 404, (await api('GET', `/api/profiles/${K1PID}`, B)).status);
  const mark = await api('POST', `/api/customer/profiles/${PID}/interest`, K1, { note: 'Likes the profile' });
  check('mark interest 201', 201, mark.status);
  const INT = mark.body?.interest;
  const INT_ID = INT?.id;
  check('interest is pending', 'pending', INT?.status);
  check('interest carries the note', 'Likes the profile', INT?.note);
  check('interest embeds the profile summary', PID, INT?.profile?.id);
  check('days_left null while pending', null, INT?.days_left);
  check('customer rows never carry agents (customer_agent)', false, 'customer_agent' in (INT || {}));
  check('customer rows never carry agents (target_agent)', false, 'target_agent' in (INT || {}));
  const dupInt = await api('POST', `/api/customer/profiles/${PID}/interest`, K1, {});
  check('duplicate interest 409', 409, dupInt.status);
  check('error code already_pending', 'already_pending', dupInt.body?.error);
  const ownInt = await api('POST', `/api/customer/profiles/${K1PID}/interest`, K1, {});
  check('interest in own profile 400', 400, ownInt.status);
  check('error code own_profile', 'own_profile', ownInt.body?.error);
  check('interest in an out-of-scope profile 404', 404, (await api('POST', `/api/customer/profiles/${OBID}/interest`, K1, {})).status);
  const rowAfterMark = (await api('GET', `/api/customer/profiles?q=Priya%20Kumari&limit=100`, K1)).body.profiles.find((x) => x.id === PID);
  check('browse row interest_status pending', 'pending', rowAfterMark?.interest_status);
  check('browse row is_interested true', true, rowAfterMark?.is_interested);
  check('detail interest.status pending', 'pending', (await api('GET', `/api/customer/profiles/${PID}`, K1)).body?.profile?.interest?.status);
  const kInterests = await api('GET', '/api/customer/interests', K1);
  check('my interests 200', 200, kInterests.status);
  check('my interests lists it with the profile name', 'Priya Kumari', kInterests.body?.interests?.find((i) => i.id === INT_ID)?.profile?.full_name);

  // The uploader (A) sees it under `received` with the customer's agent; the
  // customer's agent (C) under `clients` with the uploader — the one place
  // uploader identity crosses agents (SPEC §9.4).
  const aReceived = await api('GET', '/api/interests?box=received', A);
  check('received box 200', 200, aReceived.status);
  check('box echoed', 'received', aReceived.body?.box);
  const aInt = aReceived.body?.interests?.find((i) => i.id === INT_ID);
  assertTrue('uploader sees the interest in received', Boolean(aInt));
  check('uploader sees the customer\'s name', 'Kiran Customer', aInt?.customer?.full_name);
  check('uploader does NOT get the customer\'s phone', false, 'phone' in (aInt?.customer || {}));
  check('uploader gets customer_agent (C)', C_ID, aInt?.customer_agent?.id);
  check('… with C\'s phone', cPhone, aInt?.customer_agent?.phone);
  check('… with C\'s agency', 'C Bureau', aInt?.customer_agent?.agency_name);
  check('uploader does NOT get target_agent (that is themselves)', false, 'target_agent' in (aInt || {}));
  check('uploader sees the customer\'s profile summary', K1PID, aInt?.customer_profile?.id);
  check('uploader sees the target profile summary', PID, aInt?.profile?.id);
  check('uploader can_decide', true, aInt?.can_decide);
  const cClientsBox = await api('GET', '/api/interests?box=clients', C);
  const cInt = cClientsBox.body?.interests?.find((i) => i.id === INT_ID);
  assertTrue('customer\'s agent sees it in clients', Boolean(cInt));
  check('customer\'s agent gets the customer phone', kPhone, cInt?.customer?.phone);
  check('customer\'s agent gets target_agent (A)', A_ID, cInt?.target_agent?.id);
  check('… with A\'s phone', aPhone, cInt?.target_agent?.phone);
  check('customer\'s agent does NOT get customer_agent', false, 'customer_agent' in (cInt || {}));
  check('customer\'s agent cannot decide', false, cInt?.can_decide);
  check('C\'s received box does not have it', 0, (await api('GET', '/api/interests?box=received', C)).body?.interests?.filter((i) => i.id === INT_ID).length);
  check('unrelated agent B sees nothing', 0, (await api('GET', '/api/interests?box=received', B)).body?.interests?.filter((i) => i.id === INT_ID).length);
  check('unrelated agent D sees nothing in clients', 0, (await api('GET', '/api/interests?box=clients', D)).body?.interests?.filter((i) => i.id === INT_ID).length);
  const adminInt = (await api('GET', '/api/interests?box=received', ADMIN)).body?.interests?.find((i) => i.id === INT_ID);
  assertTrue('admin sees it with both agents', Boolean(adminInt?.customer_agent && adminInt?.target_agent));
  check('status filter pending', 1, (await api('GET', '/api/interests?box=received&status=pending', A)).body?.interests?.filter((i) => i.id === INT_ID).length);
  const cClientDetail = await api('GET', `/api/clients/${K1_ID}`, C);
  check('client detail embeds the interest', 1, cClientDetail.body?.client?.interests?.filter((i) => i.id === INT_ID).length);
  check('client detail interest carries target_agent', A_ID, cClientDetail.body?.client?.interests?.find((i) => i.id === INT_ID)?.target_agent?.id);
  check('client row interests_count 1', 1, cClientDetail.body?.client?.interests_count);
  const aNotifInt = (await api('GET', '/api/notifications', A)).body;
  assertTrue('uploader notified: counts.interests_inbox', aNotifInt?.counts?.interests_inbox >= 1);
  assertTrue('notification item interest_received', aNotifInt?.items?.some((i) => i.type === 'interest_received' && i.id === INT_ID));
  assertTrue('badge includes interests', aNotifInt?.badge >= 1);

  // Only the target profile's uploader (or an admin) decides.
  const cAccept = await api('POST', `/api/interests/${INT_ID}/accept`, C);
  check('customer\'s own agent cannot accept', 403, cAccept.status);
  check('error code not_your_profile', 'not_your_profile', cAccept.body?.error);
  check('unrelated agent cannot accept', 403, (await api('POST', `/api/interests/${INT_ID}/accept`, B)).status);
  check('unknown interest 404', 404, (await api('POST', '/api/interests/999999999/accept', A)).status);
  // C has a PENDING contact request on Priya from step 17 — acceptance must approve it (rule 5).
  check('C\'s contact request on Priya is still pending', 'pending', (await api('GET', `/api/profiles/${PID}`, C)).body?.profile?.contact_access);
  const accepted = await api('POST', `/api/interests/${INT_ID}/accept`, A);
  check('uploader accepts 200', 200, accepted.status);
  check('interest accepted', 'accepted', accepted.body?.interest?.status);
  check('days_left 15', 15, accepted.body?.interest?.days_left);
  assertTrue('access_expires_at set', Boolean(accepted.body?.interest?.access_expires_at));
  check('accept twice 409 wrong_status', 'wrong_status', (await api('POST', `/api/interests/${INT_ID}/accept`, A)).body?.error);
  const kUnlocked = (await api('GET', `/api/customer/profiles/${PID}`, K1)).body?.profile;
  check('customer now has contact_access granted', 'granted', kUnlocked?.contact_access);
  check('customer sees interest.days_left 15', 15, kUnlocked?.interest?.days_left);
  check('customer sees interest.status accepted', 'accepted', kUnlocked?.interest?.status);
  check('customer sees contact_phone', '9876543210', kUnlocked?.contact_phone);
  check('customer sees the native place', 'Hyderabad', kUnlocked?.city);
  check('customer sees family_details', 'Father is a retired teacher.', kUnlocked?.family_details);
  check('customer still never sees uploaded_by', false, 'uploaded_by' in (kUnlocked || {}));
  check('browse row interest_status accepted', 'accepted', (await api('GET', `/api/customer/profiles?q=Priya%20Kumari&limit=100`, K1)).body.profiles.find((x) => x.id === PID)?.interest_status);
  check('my interests row days_left 15', 15, (await api('GET', '/api/customer/interests', K1)).body?.interests?.find((i) => i.id === INT_ID)?.days_left);
  const reMark = await api('POST', `/api/customer/profiles/${PID}/interest`, K1, {});
  check('re-marking while accepted 409', 409, reMark.status);
  check('error code already_accepted', 'already_accepted', reMark.body?.error);
  // Auto-grant to the customer's agent: the pending request became approved.
  const cGrantedP = (await api('GET', `/api/profiles/${PID}`, C)).body?.profile;
  check('customer\'s agent contact_access granted via the interest', 'granted', cGrantedP?.contact_access);
  check('… is_mine false (not the uploader)', false, cGrantedP?.is_mine);
  check('… request status approved', 'approved', cGrantedP?.contact_request_status);
  check('… on-request block visible to the agent', 'Hyderabad', cGrantedP?.city);
  const cSentRow = (await api('GET', '/api/contact-requests?box=sent', C)).body?.contact_requests?.find((r) => r.profile_id === PID && r.status === 'approved');
  assertTrue('C\'s sent box shows the approved row', Boolean(cSentRow));
  assertTrue('… noted "via interest #id"', (cSentRow?.note || '').includes(`via interest #${INT_ID}`), cSentRow?.note);
  check('… days_left 15', 15, cSentRow?.days_left);
  check('A\'s inbox has no pending request left for Priya', 0, (await api('GET', '/api/contact-requests?box=inbox&status=pending', A)).body?.contact_requests?.filter((r) => r.profile_id === PID).length);
  const cNotifDecided = (await api('GET', '/api/notifications', C)).body;
  assertTrue('customer\'s agent notified: interest_decided', cNotifDecided?.items?.some((i) => i.type === 'interest_decided' && i.id === INT_ID));
  check('accepted filter (live only) lists it', 1, (await api('GET', '/api/interests?box=received&status=accepted', A)).body?.interests?.filter((i) => i.id === INT_ID).length);

  // Revoke ends the customer's access now (SPEC §9.4). The agent's contact row
  // is a separate log entry and is revoked through /contact-requests as usual.
  check('customer\'s agent cannot revoke', 403, (await api('POST', `/api/interests/${INT_ID}/revoke`, C)).status);
  const revoked = await api('POST', `/api/interests/${INT_ID}/revoke`, A);
  check('uploader revokes 200', 200, revoked.status);
  check('interest revoked', 'revoked', revoked.body?.interest?.status);
  check('revoke twice 409', 409, (await api('POST', `/api/interests/${INT_ID}/revoke`, A)).status);
  const kRevoked = (await api('GET', `/api/customer/profiles/${PID}`, K1)).body?.profile;
  check('customer access back to none', 'none', kRevoked?.contact_access);
  check('customer no longer sees contact_phone', false, 'contact_phone' in (kRevoked || {}));
  check('customer sees interest.status revoked', 'revoked', kRevoked?.interest?.status);
  check('browse row is_interested false after revoke', false, (await api('GET', `/api/customer/profiles?q=Priya%20Kumari&limit=100`, K1)).body.profiles.find((x) => x.id === PID)?.is_interested);
  check('revoked filter lists it for the uploader', 1, (await api('GET', '/api/interests?box=received&status=revoked', A)).body?.interests?.filter((i) => i.id === INT_ID).length);
  check('revoked reads the same for the customer\'s agent', 'revoked', (await api('GET', '/api/interests?box=clients', C)).body?.interests?.find((i) => i.id === INT_ID)?.status);

  // Re-expressing reuses the row (UNIQUE customer+profile) and goes back to pending; decline; re-express; withdraw.
  const again = await api('POST', `/api/customer/profiles/${PID}/interest`, K1, { note: 'Second try' });
  check('re-express after revoke 201', 201, again.status);
  check('same interest row is reused', INT_ID, again.body?.interest?.id);
  check('back to pending', 'pending', again.body?.interest?.status);
  check('revoke a pending one 409', 409, (await api('POST', `/api/interests/${INT_ID}/revoke`, A)).status);
  const declined = await api('POST', `/api/interests/${INT_ID}/decline`, A);
  check('uploader declines 200', 200, declined.status);
  check('interest declined', 'declined', declined.body?.interest?.status);
  check('decline twice 409', 409, (await api('POST', `/api/interests/${INT_ID}/decline`, A)).status);
  const kDeclined = (await api('GET', `/api/customer/profiles?q=Priya%20Kumari&limit=100`, K1)).body.profiles.find((x) => x.id === PID);
  check('browse row interest_status declined', 'declined', kDeclined?.interest_status);
  check('browse row is_interested false', false, kDeclined?.is_interested);
  check('re-express after decline 201 (agents may have talked since)', 201, (await api('POST', `/api/customer/profiles/${PID}/interest`, K1, {})).status);
  check('a rejected customer cannot touch interests (403)', 403, (await api('POST', `/api/customer/interests/${INT_ID}/withdraw`, K2)).status);
  check('withdrawing an unknown interest 404', 404, (await api('POST', '/api/customer/interests/999999999/withdraw', K1)).status);
  const withdrawn = await api('POST', `/api/customer/interests/${INT_ID}/withdraw`, K1);
  check('customer withdraws 200', 200, withdrawn.status);
  check('interest withdrawn', 'withdrawn', withdrawn.body?.interest?.status);
  const withdrawTwice = await api('POST', `/api/customer/interests/${INT_ID}/withdraw`, K1);
  check('withdraw twice 409', 409, withdrawTwice.status);
  check('error code wrong_status', 'wrong_status', withdrawTwice.body?.error);
  check('uploader cannot accept a withdrawn interest', 409, (await api('POST', `/api/interests/${INT_ID}/accept`, A)).status);
  check('withdrawn filter lists it', 1, (await api('GET', '/api/interests?box=received&status=withdrawn', A)).body?.interests?.filter((i) => i.id === INT_ID).length);
  check('uploader inbox count back to 0 for this one', 0, (await api('GET', '/api/notifications', A)).body?.counts?.interests_inbox);

  // Second interest, on B's bride: B is outside community A, so K1's profile
  // becomes visible to B only while the interest is pending/accepted (§9.4);
  // C has no request on it, so acceptance INSERTS the approved contact row.
  const mark2 = await api('POST', `/api/customer/profiles/${SBID}/interest`, K1, {});
  check('interest in B\'s bride 201', 201, mark2.status);
  const INT2_ID = mark2.body?.interest?.id;
  const bSeesK = await api('GET', `/api/profiles/${K1PID}`, B);
  check('B can now see the interested customer\'s profile', 200, bSeesK.status);
  check('… without the on-request block (normal contact rules)', false, 'father_phone' in (bSeesK.body?.profile || {}));
  check('… and without uploader identity', false, 'uploaded_by' in (bSeesK.body?.profile || {}));
  check('B lists it too', 1, (await api('GET', '/api/profiles?q=Kiran%20Customer', B)).body?.profiles?.filter((x) => x.id === K1PID).length);
  check('D (community A, no interest involved) sees it through the normal community rule', 200, (await api('GET', `/api/profiles/${K1PID}`, D)).status);
  check('C has no contact access on B\'s bride yet', 'none', (await api('GET', `/api/profiles/${SBID}`, C)).body?.profile?.contact_access);
  check('A (not the uploader) cannot accept', 403, (await api('POST', `/api/interests/${INT2_ID}/accept`, A)).status);
  const accepted2 = await api('POST', `/api/interests/${INT2_ID}/accept`, B);
  check('B accepts 200', 200, accepted2.status);
  check('B\'s row carries customer_agent C', C_ID, accepted2.body?.interest?.customer_agent?.id);
  const kUnlocked2 = (await api('GET', `/api/customer/profiles/${SBID}`, K1)).body?.profile;
  check('customer unlocked: native place', 'Ongole', kUnlocked2?.city);
  check('customer unlocked: siblings count', 2, kUnlocked2?.siblings_count);
  check('customer unlocked: days_left 15', 15, kUnlocked2?.interest?.days_left);
  const cGranted2 = (await api('GET', `/api/profiles/${SBID}`, C)).body?.profile;
  check('customer\'s agent auto-granted on B\'s bride', 'granted', cGranted2?.contact_access);
  check('… is_mine false', false, cGranted2?.is_mine);
  check('… sees the contact phone', '9844444444', cGranted2?.contact_phone);
  const cSent2 = (await api('GET', '/api/contact-requests?box=sent&status=approved', C)).body?.contact_requests?.find((r) => r.profile_id === SBID);
  assertTrue('an approved contact_requests row was inserted for C', Boolean(cSent2));
  assertTrue('… noted via interest', (cSent2?.note || '').includes(`via interest #${INT2_ID}`), cSent2?.note);
  check('… days_left 15', 15, cSent2?.days_left);
  const contactLog = (await api('GET', `/api/admin/logs/contacts?profile_id=${SBID}`, ADMIN)).body?.logs?.find((l) => l.requester_id === C_ID);
  assertTrue('the acceptance is in the admin contact log (rule 5)', Boolean(contactLog));
  check('… decided by the accepting agent', 'Agent B', contactLog?.decided_by_name);
  check('B\'s inbox lists the auto-approved row with the requester', 'Agent C',
    (await api('GET', '/api/contact-requests?box=inbox&status=approved', B)).body?.contact_requests?.find((r) => r.profile_id === SBID)?.requester?.full_name);
  check('accepting again while live 409', 409, (await api('POST', `/api/interests/${INT2_ID}/accept`, B)).status);
  check('B revokes 200', 200, (await api('POST', `/api/interests/${INT2_ID}/revoke`, B)).status);
  check('customer access ended', 'none', (await api('GET', `/api/customer/profiles/${SBID}`, K1)).body?.profile?.contact_access);
  check('B loses sight of the customer\'s profile once the interest is over', 404, (await api('GET', `/api/profiles/${K1PID}`, B)).status);
  check('admin can decide any interest: re-express then admin accepts', 201, (await api('POST', `/api/customer/profiles/${SBID}/interest`, K1, {})).status);
  const adminAccept = await api('POST', `/api/interests/${INT2_ID}/accept`, ADMIN);
  check('admin accept 200', 200, adminAccept.status);
  check('admin decline of an accepted one 409', 409, (await api('POST', `/api/interests/${INT2_ID}/decline`, ADMIN)).status);
  check('admin revoke 200', 200, (await api('POST', `/api/interests/${INT2_ID}/revoke`, ADMIN)).status);
  // Leave one pending interest (on A's bride MFID) for the admin stats in step 36.
  const mark3 = await api('POST', `/api/customer/profiles/${MFID}/interest`, K1, { note: 'For the stats' });
  check('a third interest stays pending', 'pending', mark3.body?.interest?.status);
  const INT3_ID = mark3.body?.interest?.id;

  // ---------------------------------------------------------------- agent change
  step('33. Changing agent (SPEC §9.6): directory, request, the CURRENT agent decides, admin reassign');
  const myCity = await api('PATCH', '/api/my/account', A, { city: 'Vijayawada' });
  check('agent sets their directory city 200', 200, myCity.status);
  check('city echoed', 'Vijayawada', myCity.body?.agent?.city);
  check('empty account PATCH 400', 400, (await api('PATCH', '/api/my/account', A, {})).status);
  const dir = await api('GET', '/api/customer/agents', K1);
  check('directory 200', 200, dir.status);
  const dirIds = (dir.body?.agents || []).map((a) => a.id);
  check('current agent listed first', C_ID, dir.body?.agents?.[0]?.id);
  check('… flagged is_current', true, dir.body?.agents?.[0]?.is_current);
  assertTrue('directory lists the active agents A, B, D', [A_ID, B_ID, D_ID].every((id) => dirIds.includes(id)));
  check('pending agent X is not listed', false, dirIds.includes(X_ID));
  const dirA = dir.body?.agents?.find((a) => a.id === A_ID);
  check('directory card has agency', 'A Bureau', dirA?.agency_name);
  check('directory card has phone', aPhone, dirA?.phone);
  check('directory card has city', 'Vijayawada', dirA?.city);
  check('directory card has communities', COMM_A, dirA?.communities?.[0]?.id);
  check('directory card is_current false for others', false, dirA?.is_current);
  check('q filter finds A', true, ((await api('GET', '/api/customer/agents?q=Agent%20A', K1)).body?.agents || []).some((a) => a.id === A_ID));
  const byComm = ((await api('GET', `/api/customer/agents?community_id=${COMM_B}`, K1)).body?.agents || []).map((a) => a.id);
  assertTrue('community filter keeps B and C, drops A', byComm.includes(B_ID) && byComm.includes(C_ID) && !byComm.includes(A_ID));
  const byCity = ((await api('GET', '/api/customer/agents?city=vijay', K1)).body?.agents || []).map((a) => a.id);
  assertTrue('city filter finds A only (of ours)', byCity.includes(A_ID) && !byCity.includes(B_ID));

  const sameAgent = await api('POST', '/api/customer/agent-change', K1, { to_agent_id: C_ID });
  check('asking for the current agent 400', 400, sameAgent.status);
  check('error code same_agent', 'same_agent', sameAgent.body?.error);
  check('unknown agent 404', 404, (await api('POST', '/api/customer/agent-change', K1, { to_agent_id: 999999999 })).status);
  check('pending agent 400 agent_not_active', 'agent_not_active', (await api('POST', '/api/customer/agent-change', K1, { to_agent_id: X_ID })).body?.error);
  const change1 = await api('POST', '/api/customer/agent-change', K1, { to_agent_id: A_ID, note: 'Moving closer to home' });
  check('request 201', 201, change1.status);
  const CH1 = change1.body?.agent_change_request;
  check('request pending', 'pending', CH1?.status);
  check('from_agent is C', C_ID, CH1?.from_agent?.id);
  check('to_agent is A', A_ID, CH1?.to_agent?.id);
  check('customer view has no customer block', false, 'customer' in (CH1 || {}));
  check('second request 409 already_pending', 'already_pending', (await api('POST', '/api/customer/agent-change', K1, { to_agent_id: B_ID })).body?.error);
  check('my requests list it', 1, (await api('GET', '/api/customer/agent-change', K1)).body?.agent_change_requests?.filter((r) => r.id === CH1.id).length);
  check('me shows the pending change', A_ID, (await api('GET', '/api/customer/auth/me', K1)).body?.customer?.pending_agent_change?.to_agent?.id);
  check('client row shows the pending change', A_ID, (await api('GET', `/api/clients/${K1_ID}`, C)).body?.client?.pending_agent_change?.to_agent?.id);
  check('client detail embeds it', 1, (await api('GET', `/api/clients/${K1_ID}`, C)).body?.client?.agent_change_requests?.length);
  const cOut = (await api('GET', '/api/agent-change-requests?box=outgoing', C)).body;
  const cOutRow = cOut?.agent_change_requests?.find((r) => r.id === CH1.id);
  assertTrue('current agent sees it in outgoing', Boolean(cOutRow));
  check('… box outgoing', 'outgoing', cOutRow?.box);
  check('… can_decide', true, cOutRow?.can_decide);
  check('… with the customer phone', kPhone, cOutRow?.customer?.phone);
  check('… with the customer profile summary', K1PID, cOutRow?.customer_profile?.id);
  const aIn = (await api('GET', '/api/agent-change-requests?box=incoming', A)).body?.agent_change_requests?.find((r) => r.id === CH1.id);
  assertTrue('new agent sees it in incoming', Boolean(aIn));
  check('… box incoming', 'incoming', aIn?.box);
  check('… read-only', false, aIn?.can_decide);
  check('… without the customer phone yet', false, 'phone' in (aIn?.customer || {}));
  check('A\'s outgoing is empty of it', 0, (await api('GET', '/api/agent-change-requests?box=outgoing', A)).body?.agent_change_requests?.filter((r) => r.id === CH1.id).length);
  check('B sees nothing', 0, (await api('GET', '/api/agent-change-requests?box=incoming', B)).body?.agent_change_requests?.filter((r) => r.id === CH1.id).length);
  const aApprove = await api('POST', `/api/agent-change-requests/${CH1.id}/approve`, A);
  check('the NEW agent cannot approve', 403, aApprove.status);
  check('error code not_your_client', 'not_your_client', aApprove.body?.error);
  check('an unrelated agent cannot reject', 403, (await api('POST', `/api/agent-change-requests/${CH1.id}/reject`, B)).status);
  const cNotifChange = (await api('GET', '/api/notifications', C)).body;
  assertTrue('current agent notified: counts.agent_change_inbox', cNotifChange?.counts?.agent_change_inbox >= 1);
  assertTrue('notification item agent_change_requested', cNotifChange?.items?.some((i) => i.type === 'agent_change_requested' && i.id === CH1.id));

  // Cancel, then reject, then approve.
  check('customer cancels 200', 200, (await api('POST', `/api/customer/agent-change/${CH1.id}/cancel`, K1)).status);
  check('cancel twice 409', 409, (await api('POST', `/api/customer/agent-change/${CH1.id}/cancel`, K1)).status);
  check('approving a cancelled request 409', 409, (await api('POST', `/api/agent-change-requests/${CH1.id}/approve`, C)).status);
  const change2 = await api('POST', '/api/customer/agent-change', K1, { to_agent_id: A_ID });
  check('new request after cancel 201', 201, change2.status);
  const rejectedCh = await api('POST', `/api/agent-change-requests/${change2.body.agent_change_request.id}/reject`, C);
  check('current agent rejects 200', 200, rejectedCh.status);
  check('request rejected', 'rejected', rejectedCh.body?.agent_change_request?.status);
  check('customer still with C', C_ID, (await api('GET', '/api/customer/auth/me', K1)).body?.customer?.agent?.id);
  check('customer sees it rejected', 'rejected', (await api('GET', '/api/customer/agent-change', K1)).body?.agent_change_requests?.[0]?.status);
  const change3 = await api('POST', '/api/customer/agent-change', K1, { to_agent_id: A_ID });
  const CH3_ID = change3.body?.agent_change_request?.id;
  const approvedCh = await api('POST', `/api/agent-change-requests/${CH3_ID}/approve`, C);
  check('current agent approves 200', 200, approvedCh.status);
  check('request approved', 'approved', approvedCh.body?.agent_change_request?.status);
  check('approve twice 409', 409, (await api('POST', `/api/agent-change-requests/${CH3_ID}/approve`, C)).status);
  const kMoved = (await api('GET', '/api/customer/auth/me', K1)).body?.customer;
  check('customer now attached to A', A_ID, kMoved?.agent?.id);
  check('no pending change left', null, kMoved?.pending_agent_change);
  const aOwns = (await api('GET', `/api/profiles/${K1PID}`, A)).body?.profile;
  check('profile uploaded_by moved to A', A_ID, aOwns?.uploaded_by);
  check('A can edit it now', true, aOwns?.can_edit);
  check('C no longer owns it', false, (await api('GET', `/api/profiles/${K1PID}`, C)).body?.profile?.can_edit);
  check('A lists the customer under Clients (active)', 'active', (await api('GET', '/api/clients', A)).body?.clients?.find((x) => x.id === K1_ID)?.status);
  check('C no longer lists the customer', 0, (await api('GET', '/api/clients', C)).body?.clients?.filter((x) => x.id === K1_ID).length);
  check('C cannot open the client any more', 403, (await api('GET', `/api/clients/${K1_ID}`, C)).status);
  assertTrue('new agent notified: agent_change_decided', ((await api('GET', '/api/notifications', A)).body?.items || []).some((i) => i.type === 'agent_change_decided' && i.id === CH3_ID));
  check('incoming row now carries the customer phone for A', kPhone, (await api('GET', '/api/agent-change-requests?box=incoming', A)).body?.agent_change_requests?.find((r) => r.id === CH3_ID)?.customer?.phone);
  // Browse scope follows the new agent: A is only in community A.
  check('bride in community B no longer visible to the customer', 0, await seesInBrowse('q=Scope%20Test%20Bride', SBID));
  check('Priya (community A) still visible', 1, await seesInBrowse('q=Priya%20Kumari&limit=100', PID));
  check('me lists A\'s communities (1)', 1, kMoved?.agent?.communities?.length);

  // Admin reassign (SPEC §9.5) — back to C; a pending request gets cancelled on the way.
  const change4 = await api('POST', '/api/customer/agent-change', K1, { to_agent_id: D_ID });
  check('customer asks for D meanwhile 201', 201, change4.status);
  check('agent cannot use the admin reassign', 403, (await api('PUT', `/api/admin/customers/${K1_ID}/agent`, A, { agent_id: C_ID })).status);
  check('reassign to the same agent 400 same_agent', 'same_agent', (await api('PUT', `/api/admin/customers/${K1_ID}/agent`, ADMIN, { agent_id: A_ID })).body?.error);
  check('reassign to a pending agent 400 agent_not_active', 'agent_not_active', (await api('PUT', `/api/admin/customers/${K1_ID}/agent`, ADMIN, { agent_id: X_ID })).body?.error);
  check('reassign to an unknown agent 404', 404, (await api('PUT', `/api/admin/customers/${K1_ID}/agent`, ADMIN, { agent_id: 999999999 })).status);
  const reassigned = await api('PUT', `/api/admin/customers/${K1_ID}/agent`, ADMIN, { agent_id: C_ID });
  check('admin reassign 200', 200, reassigned.status);
  check('admin row carries the new agent', C_ID, reassigned.body?.customer?.agent?.id);
  check('pending request was cancelled by the reassign', null, reassigned.body?.customer?.pending_agent_change);
  check('customer sees the cancelled request', 'cancelled', (await api('GET', '/api/customer/agent-change', K1)).body?.agent_change_requests?.find((r) => r.id === change4.body.agent_change_request.id)?.status);
  check('customer back with C', C_ID, (await api('GET', '/api/customer/auth/me', K1)).body?.customer?.agent?.id);
  check('profile uploaded_by back to C', C_ID, (await api('GET', `/api/profiles/${K1PID}`, C)).body?.profile?.uploaded_by);

  // ---------------------------------------------------------------- registration form
  step('34. Registration form /r/:token (SPEC §9.3-B): public HTML, one transaction, OTP login afterwards');
  const formPage = await raw(REG_URL);
  check('GET form 200', 200, formPage.status);
  assertTrue('form is HTML', (formPage.headers.get('content-type') || '').includes('text/html'));
  check('form is noindex', 'noindex, nofollow', formPage.headers.get('x-robots-tag'));
  assertTrue('form names the agent', formPage.text.includes('Agent C') && formPage.text.includes('C Bureau'));
  assertTrue('form is branded Gandharva', formPage.text.includes('Gandharva'));
  for (const field of ['phone', 'full_name', 'gender', 'community_id', 'edu_graduation', 'edu_graduation_country', 'elder_sisters', 'property_share', 'photos', 'work_country_id', 'occupation_type_id']) {
    assertTrue(`form has the ${field} field`, formPage.text.includes(`name="${field}"`));
  }
  assertTrue('form embeds the community list', formPage.text.includes(m.communities[0].name));
  check('bad token 404', 404, (await raw(`${BASE}/r/deadbeefdeadbeefdeadbeef`)).status);
  check('rotated (old) token 404', 404, (await raw(OLD_REG_URL)).status);
  check('path traversal 404', 404, (await raw(`${BASE}/r/..%2F..%2Fetc%2Fpasswd`)).status);

  const fPhone = randomPhone('7');
  const OCC = m.occupation_types?.[0]?.id;
  const formSubName = `FormSub${Date.now() % 100000}`;
  const formFields = {
    phone: `0${fPhone}`, full_name: 'Form Bride', gender: 'bride', dob: '1996-05-20', marital_status_id: MSTAT,
    birth_time: '06:15', birth_place: 'Tenali', birth_state: 'Andhra Pradesh', birth_country_id: INDIA, nationality_id: INDIA,
    community_id: COMM_A, subcaste_name: formSubName, gothram: 'Kaundinya', city: 'Tenali', state: 'Andhra Pradesh',
    height_ft: 5, height_in: 4, weight_kg: 54,
    edu_10th: 'SSC Board', edu_10th_country: INDIA, edu_graduation: 'B.Tech CSE', edu_graduation_country: USA,
    education_id: EDU, occupation_type_id: OCC, profession_id: PROF, income_text: '9 LPA', other_income: 'Rent 1 LPA',
    work_place: 'Guntur', work_country_id: INDIA,
    father_name: 'Form Father', father_occupation: 'Farmer', father_phone: '9855555555', mother_name: 'Form Mother',
    contact_name: 'Form Father', contact_phone: '9855555555',
    elder_sisters: 1, younger_brothers: 2, family_details: 'Joint family in Tenali.',
    property_share: 'One third', property_details: 'Farm land, 2 acres', about: 'Loves music.',
  };
  const buildForm = (fields, photos = 2) => {
    const form = new FormData();
    for (const [k, v] of Object.entries(fields)) if (v !== undefined && v !== null) form.append(k, String(v));
    for (let i = 0; i < photos; i++) form.append('photos', new Blob([TINY_JPEG], { type: 'image/jpeg' }), `p${i}.jpg`);
    return form;
  };
  const submitted = await raw(REG_URL, { method: 'POST', form: buildForm(formFields) });
  check('POST form 200 (thank-you page)', 200, submitted.status);
  assertTrue('thank-you page names the person and the agent', submitted.text.includes('Thank you, Form Bride') && submitted.text.includes('Agent C'));
  assertTrue('thank-you page shows the login number', submitted.text.includes(fPhone));
  const fClient = (await api('GET', `/api/clients?q=${fPhone}`, C)).body?.clients?.find((x) => x.phone === fPhone);
  assertTrue('the customer exists under agent C', Boolean(fClient));
  const F_ID = fClient?.id;
  check('form customer is pending', 'pending', fClient?.status);
  check('form customer source form', 'form', fClient?.source);
  check('phone not verified yet', null, fClient?.phone_verified_at);
  check('profile created with it', 'Form Bride', fClient?.profile?.full_name);
  check('profile is hidden', 'hidden', fClient?.profile?.status);
  const FPID = fClient?.profile?.id;
  const fProfile = (await api('GET', `/api/profiles/${FPID}`, C)).body?.profile;
  check('uploaded_by is the agent', C_ID, fProfile?.uploaded_by);
  check('customer_id set', F_ID, fProfile?.customer_id);
  check('feet + inches → 163 cm', 163, fProfile?.height_cm);
  check('2 photos stored', 2, fProfile?.photos?.length);
  check('subcaste created from the form', formSubName, fProfile?.subcaste?.name);
  check('nationality India', 'India', fProfile?.nationality?.name);
  check('work country India', 'India', fProfile?.work_country?.name);
  check('occupation type saved', m.occupation_types?.[0]?.name, fProfile?.occupation_type?.name);
  check('other income saved', 'Rent 1 LPA', fProfile?.other_income);
  check('education levels saved (2)', 2, fProfile?.education_levels?.length);
  check('levels ordered 10th first', '10th', fProfile?.education_levels?.[0]?.level);
  check('10th details', 'SSC Board', fProfile?.education_levels?.[0]?.details);
  check('graduation country United States', 'United States', fProfile?.education_levels?.[1]?.country?.name);
  check('siblings: has_siblings true', true, fProfile?.has_siblings);
  check('siblings: count = sum of the four boxes (3)', 3, fProfile?.siblings_count);
  check('siblings: elder_sisters 1', 1, fProfile?.elder_sisters);
  check('siblings: younger_brothers 2', 2, fProfile?.younger_brothers);
  check('siblings: elder_brothers 0', 0, fProfile?.elder_brothers);
  check('property share saved', 'One third', fProfile?.property_share);
  check('property details saved', 'Farm land, 2 acres', fProfile?.property_details);
  check('birth state saved', 'Andhra Pradesh', fProfile?.birth_state);
  check('birth country India', 'India', fProfile?.birth_country?.name);
  check('father occupation saved', 'Farmer', fProfile?.father_occupation);
  check('birth time saved', '06:15', fProfile?.birth_time);
  check('hidden form profile invisible to other agents', 404, (await api('GET', `/api/profiles/${FPID}`, A)).status);

  const dupForm = await raw(REG_URL, { method: 'POST', form: buildForm(formFields, 0) });
  check('same number again 409 page', 409, dupForm.status);
  assertTrue('409 page says already registered', dupForm.text.includes('already registered'));
  const badForm = await raw(REG_URL, { method: 'POST', form: buildForm({ ...formFields, phone: randomPhone('6'), full_name: '', dob: '2020-01-01' }, 0) });
  check('validation error re-renders the form 400', 400, badForm.status);
  assertTrue('… with an error banner', badForm.text.includes('Please check these details'));
  assertTrue('… naming the fields', badForm.text.includes('Full name') && badForm.text.includes('Date of birth'));
  assertTrue('… keeping what was typed', badForm.text.includes('value="Kaundinya"'));
  check('POST on the old token 404', 404, (await raw(OLD_REG_URL, { method: 'POST', form: buildForm({ ...formFields, phone: randomPhone('6') }, 0) })).status);
  check('nothing was created by the failed submissions', 1, (await api('GET', `/api/clients?q=Form%20Bride`, C)).body?.clients?.filter((x) => x.full_name === 'Form Bride' && x.phone === fPhone).length);

  // The form customer's first Gandharva login: OTP verifies the number.
  const fLogin = await customerOtp(fPhone);
  check('form customer OTP login 200', 200, fLogin.verify.status);
  check('… is a login, not a new signup', undefined, fLogin.verify.body?.new);
  const F1 = fLogin.verify.body?.token;
  assertTrue('… returns a customer token', Boolean(F1));
  check('… customer pending', 'pending', fLogin.verify.body?.customer?.status);
  check('… source form', 'form', fLogin.verify.body?.customer?.source);
  assertTrue('… phone_verified_at now set', Boolean(fLogin.verify.body?.customer?.phone_verified_at));
  check('… has_profile true', true, fLogin.verify.body?.customer?.has_profile);
  const fOwn = await api('GET', '/api/customer/profile', F1);
  check('form customer sees their own (hidden) profile', 200, fOwn.status);
  check('… hidden', 'hidden', fOwn.body?.profile?.status);
  check('… with the on-request block', 'Form Father', fOwn.body?.profile?.father_name);
  check('… browses only as a guest', 'guest', (await api('GET', '/api/customer/profiles', F1)).body?.access);
  check('… the form profile is unpaid', 'payment_pending', fOwn.body?.profile?.visibility);
  const fOrder = await api('POST', `/api/customer/my-profiles/${fOwn.body?.profile?.id}/payment`, F1);
  check('… pays the fee in the app', 'paid', (await api('POST', `/api/customer/payments/${fOrder.body?.payment?.id}/confirm`, F1, {})).body?.payment?.status);

  // ---------------------------------------------------------------- new profile fields
  step('35. Registration-form fields (SPEC §9.7): education levels, occupation type, nationality, work country');
  assertTrue('occupation types seeded', (m.occupation_types?.length ?? 0) >= 5);
  const OCC2 = m.occupation_types?.[1]?.id;
  const ff = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Fields Test Groom', gender: 'groom', dob: '1992-11-11', height_cm: 178, community_id: COMM_A,
    nationality_id: INDIA, work_country_id: USA, occupation_type_id: OCC2, other_income: 'Rental 2 LPA',
    birth_state: 'Telangana', birth_country_id: INDIA, father_occupation: 'Farmer', mother_occupation: 'Homemaker',
    education_levels: JSON.stringify([{ level: 'graduation', details: 'B.Tech', country_id: USA }, { level: '10th', details: 'SSC' }]),
    has_siblings: 'true', siblings_count: 1, elder_brothers: 1, property_share: 'Half', property_details: 'House in Warangal',
    contact_phone: '9866666666', about: 'Engineer abroad.',
  }, [{ buffer: TINY_JPEG, name: 'f.jpg', type: 'image/jpeg' }]);
  check('create with the new fields 201', 201, ff.status);
  const FF = ff.body?.profile;
  const FFID = FF?.id;
  check('nationality resolved', 'India', FF?.nationality?.name);
  check('work country resolved', 'United States', FF?.work_country?.name);
  check('occupation type resolved', m.occupation_types?.[1]?.name, FF?.occupation_type?.name);
  check('other income saved', 'Rental 2 LPA', FF?.other_income);
  check('education levels saved (2)', 2, FF?.education_levels?.length);
  check('levels come back in level order (10th first)', '10th', FF?.education_levels?.[0]?.level);
  check('graduation carries its country', 'United States', FF?.education_levels?.[1]?.country?.name);
  check('level without a country reads null', null, FF?.education_levels?.[0]?.country);
  check('birth state (uploader)', 'Telangana', FF?.birth_state);
  check('birth country (uploader)', 'India', FF?.birth_country?.name);
  check('father occupation (uploader)', 'Farmer', FF?.father_occupation);
  check('elder brothers (uploader)', 1, FF?.elder_brothers);
  check('property share (uploader)', 'Half', FF?.property_share);
  const ffRow = (await api('GET', '/api/profiles?q=Fields%20Test', C)).body?.profiles?.find((x) => x.id === FFID);
  check('list row carries nationality', 'India', ffRow?.nationality?.name);
  check('list row carries work_country', 'United States', ffRow?.work_country?.name);
  check('list row carries occupation_type', m.occupation_types?.[1]?.name, ffRow?.occupation_type?.name);
  check('list row carries other_income', 'Rental 2 LPA', ffRow?.other_income);
  check('list row carries education_levels', 2, ffRow?.education_levels?.length);
  for (const key of ['birth_state', 'birth_country', 'father_occupation', 'mother_occupation', 'elder_brothers', 'property_share', 'property_details']) {
    check(`list row omits ${key}`, false, key in (ffRow || {}));
  }
  const ffOther = (await api('GET', `/api/profiles/${FFID}`, C)).body?.profile;
  for (const key of ['birth_state', 'birth_country', 'father_occupation', 'property_share', 'property_details', 'elder_brothers']) {
    check(`other agent detail omits ${key}`, false, key in (ffOther || {}));
  }
  check('other agent detail keeps education_levels', 2, ffOther?.education_levels?.length);
  const hasF = async (qs) => (await api('GET', `/api/profiles?${qs}`, A)).body.profiles.filter((x) => x.id === FFID).length;
  check('occupation_type_id filter finds it', 1, await hasF(`occupation_type_id=${OCC2}&q=Fields`));
  check('other occupation type excludes it', 0, await hasF(`occupation_type_id=${OCC}&q=Fields`));
  check('work_country_id=US finds it', 1, await hasF(`work_country_id=${USA}&q=Fields`));
  check('work_country_id=UK excludes it', 0, await hasF(`work_country_id=${UK}&q=Fields`));
  check('unknown occupation type 400', 400, (await api('PATCH', `/api/profiles/${FFID}`, A, { occupation_type_id: 999999 })).status);
  check('unknown nationality 400', 400, (await api('PATCH', `/api/profiles/${FFID}`, A, { nationality_id: 999999 })).status);
  check('unknown work country 400', 400, (await api('PATCH', `/api/profiles/${FFID}`, A, { work_country_id: 999999 })).status);
  const replaced = await api('PATCH', `/api/profiles/${FFID}`, A, { education_levels: [{ level: 'post_graduation', details: 'M.Tech' }] });
  check('PATCH education_levels replaces the set', 1, replaced.body?.profile?.education_levels?.length);
  check('… with the new level', 'post_graduation', replaced.body?.profile?.education_levels?.[0]?.level);
  const dupLevel = await api('PATCH', `/api/profiles/${FFID}`, A, { education_levels: [{ level: '10th' }, { level: '10th' }] });
  check('duplicate level 400', 400, dupLevel.status);
  check('error code validation_failed', 'validation_failed', dupLevel.body?.error);
  check('unknown level 400', 400, (await api('PATCH', `/api/profiles/${FFID}`, A, { education_levels: [{ level: 'phd' }] })).status);
  check('unknown level country 400 invalid_reference', 'invalid_reference', (await api('PATCH', `/api/profiles/${FFID}`, A, { education_levels: [{ level: '10th', country_id: 999999 }] })).body?.error);
  check('PATCH education_levels: [] clears', 0, (await api('PATCH', `/api/profiles/${FFID}`, A, { education_levels: [] })).body?.profile?.education_levels?.length);
  await api('PATCH', `/api/profiles/${FFID}`, A, { education_levels: [{ level: 'graduation', details: 'B.Tech', country_id: USA }] });
  check('PATCH other_income null clears', null, (await api('PATCH', `/api/profiles/${FFID}`, A, { other_income: '' })).body?.profile?.other_income);
  await api('PATCH', `/api/profiles/${FFID}`, A, { other_income: 'Rental 2 LPA' });

  const ffShare = await api('POST', `/api/profiles/${FFID}/share`, C, { method: 'whatsapp' });
  const ffText = ffShare.body?.whatsapp_text || '';
  assertTrue('share text says "Works in United States"', ffText.includes('Works in United States'), ffText);
  assertTrue('share text has NO father occupation / property', !ffText.includes('Farmer') && !ffText.includes('Half'), ffText);
  const ffHtml = (await raw(ffShare.body.share_url)).text;
  assertTrue('public page has "Works in" + the country', /Works in<\/dt><dd>United States/.test(ffHtml));
  assertTrue('public page shows nationality', /Nationality<\/dt><dd>India/.test(ffHtml));
  assertTrue('public page shows qualifications by level', ffHtml.includes('Qualifications') && ffHtml.includes('B.Tech') && ffHtml.includes('(United States)'));
  assertTrue('public page shows the occupation type', ffHtml.includes(m.occupation_types[1].name));
  assertTrue('public page shows other income', ffHtml.includes('Rental 2 LPA'));
  assertTrue('public page has NO birth state / parents\' occupations / property', !ffHtml.includes('Telangana') && !ffHtml.includes('Farmer') && !ffHtml.includes('Homemaker') && !ffHtml.includes('Warangal'));
  assertTrue('public page has NO siblings', !/Siblings<\/dt>/.test(ffHtml));
  const ffCard = await raw(`${BASE}/api/profiles/${FFID}/share`, { method: 'POST', token: C, json: { method: 'download' } });
  check('download card renders 200', 200, ffCard.status);
  const ffPdf = await raw(`${BASE}/api/profiles/${FFID}/share`, { method: 'POST', token: C, json: { method: 'pdf' } });
  check('PDF renders 200', 200, ffPdf.status);
  assertTrue('PDF starts with %PDF', ffPdf.buffer.subarray(0, 4).toString() === '%PDF');
  const ffCustomerRow = (await api('GET', '/api/customer/profiles?gender=groom&q=Fields%20Test', K1)).body?.profiles?.find((x) => x.id === FFID);
  check('customer browse row carries work_country', 'United States', ffCustomerRow?.work_country?.name);
  check('customer browse row carries occupation_type', m.occupation_types?.[1]?.name, ffCustomerRow?.occupation_type?.name);
  check('customer browse row omits father_occupation', false, 'father_occupation' in (ffCustomerRow || {}));

  // ---------------------------------------------------------------- admin customers + stats
  step('36. Admin customers and stats (SPEC §9.5)');
  check('agent blocked from admin customers', 403, (await api('GET', '/api/admin/customers', C)).status);
  check('agent blocked from admin customer actions', 403, (await api('POST', `/api/admin/customers/${K2_ID}/activate`, C)).status);
  const adminCustomers = await api('GET', '/api/admin/customers', ADMIN);
  check('admin customers 200', 200, adminCustomers.status);
  const adminK1 = adminCustomers.body?.customers?.find((x) => x.id === K1_ID);
  check('rows carry the owning agent', C_ID, adminK1?.agent?.id);
  check('… with the agent name', 'Agent C', adminK1?.agent?.full_name);
  check('… and the customer phone', kPhone, adminK1?.phone);
  check('status filter rejected finds K2', 1, (await api('GET', '/api/admin/customers?status=rejected', ADMIN)).body?.customers?.filter((x) => x.id === K2_ID).length);
  check('status filter pending finds the form customer', 1, (await api('GET', '/api/admin/customers?status=pending', ADMIN)).body?.customers?.filter((x) => x.id === F_ID).length);
  check('q filter by phone', 1, (await api('GET', `/api/admin/customers?q=${kPhone}`, ADMIN)).body?.customers?.length);
  const statsBefore = (await api('GET', '/api/admin/stats', ADMIN)).body?.stats;
  for (const key of ['pending_customers', 'active_customers', 'pending_interests', 'pending_agent_changes']) {
    assertTrue(`stats has ${key}`, typeof statsBefore?.[key] === 'number');
  }
  assertTrue('stats count the pending form customer', statsBefore?.pending_customers >= 1);
  assertTrue('stats count the active customer', statsBefore?.active_customers >= 1);
  assertTrue('stats count the pending interest', statsBefore?.pending_interests >= 1);
  const adminActivate = await api('POST', `/api/admin/customers/${K2_ID}/activate`, ADMIN);
  check('admin re-activates a rejected customer 200', 200, adminActivate.status);
  check('… now active', 'active', adminActivate.body?.customer?.status);
  assertTrue('… approved_at stamped', Boolean(adminActivate.body?.customer?.approved_at));
  check('… active without a paid profile browses as a guest', 'guest', (await api('GET', '/api/customer/profiles', K2)).body?.access);
  check('… gender param works for guests', 200, (await api('GET', '/api/customer/profiles?gender=bride', K2)).status);
  check('admin suspend 200', 200, (await api('POST', `/api/admin/customers/${K2_ID}/suspend`, ADMIN)).status);
  check('admin reject a suspended one 409', 409, (await api('POST', `/api/admin/customers/${K2_ID}/reject`, ADMIN)).status);
  check('admin activate again 200', 200, (await api('POST', `/api/admin/customers/${K2_ID}/activate`, ADMIN)).status);
  check('admin approves the form customer 200', 200, (await api('POST', `/api/admin/customers/${F_ID}/activate`, ADMIN)).status);
  check('form profile went active with the approval', 'active', (await api('GET', '/api/customer/profile', F1)).body?.profile?.status);
  check('form profile now visible to agent A', 200, (await api('GET', `/api/profiles/${FPID}`, A)).status);
  check('admin activate an active customer 409', 409, (await api('POST', `/api/admin/customers/${F_ID}/activate`, ADMIN)).status);
  check('unknown customer 404', 404, (await api('POST', '/api/admin/customers/999999999/activate', ADMIN)).status);
  const statsAfter = (await api('GET', '/api/admin/stats', ADMIN)).body?.stats;
  assertTrue('active_customers grew by 2', statsAfter?.active_customers === statsBefore?.active_customers + 2);
  assertTrue('pending_customers dropped by 1', statsAfter?.pending_customers === statsBefore?.pending_customers - 1);
  check('admin declines the leftover interest (stats tidy)', 200, (await api('POST', `/api/interests/${INT3_ID}/decline`, ADMIN)).status);

  // ---------------------------------------------------------------- 37. review fixes
  step('37. Review fixes: shortlist rows, suspended customers, revoke cascade, bad input');
  const PROTECTED_KEYS = [
    'city', 'state', 'birth_place', 'birth_state', 'birth_country', 'work_place', 'nri_place',
    'father_name', 'father_occupation', 'father_phone', 'mother_name', 'mother_occupation', 'mother_phone',
    'contact_name', 'contact_phone', 'has_siblings', 'siblings_count', 'siblings_details',
    'elder_sisters', 'younger_sisters', 'elder_brothers', 'younger_brothers',
    'family_details', 'property_share', 'property_details',
  ];
  const hasProtected = (obj) => PROTECTED_KEYS.some((k) => obj && Object.prototype.hasOwnProperty.call(obj, k));

  // (a) shortlist rows carry the public location only — never the native place.
  const slReview = await api('POST', `/api/profiles/${PID}/shortlist`, C, { client_label: 'review fix' });
  check('shortlist P for the review check 201', 201, slReview.status);
  const slGroups = (await api('GET', '/api/shortlists', C)).body?.groups ?? [];
  const slRow = slGroups.flatMap((g) => g.profiles ?? []).find((e) => e.profile_id === PID);
  assertTrue('shortlist row found', Boolean(slRow));
  check('shortlist row has no protected keys', false, hasProtected(slRow));
  assertTrue('shortlist row carries work_country / nri_country keys', slRow && 'work_country' in slRow && 'nri_country' in slRow);
  check('delete the review shortlist 200', 200, (await api('DELETE', `/api/shortlists/${slReview.body?.shortlist?.id}`, C)).status);

  // (b) a fresh agent E + customer M under E, so the revoke cascade is observed on a clean pair.
  const ePhone = randomPhone('7');
  const signupE = await signupAgent({
    full_name: 'Agent E', phone: ePhone, password: 'secret123', agency_name: 'E Bureau', community_ids: [COMM_A],
  });
  check('agent E signup 201', 201, signupE.status);
  const E = signupE.body?.token;
  check('admin activates E', 200, (await api('POST', `/api/admin/agents/${signupE.body?.agent?.id}/activate`, ADMIN)).status);
  const mPhone = randomPhone('6');
  const signupM = await signupCustomer({ full_name: 'Meena Customer', phone: mPhone, agent_phone: ePhone });
  check('customer M signup 201', 201, signupM.status);
  const M = signupM.body?.token;
  const M_ID = signupM.body?.customer?.id;
  check('E approves M', 200, (await api('POST', `/api/clients/${M_ID}/approve`, E)).status);
  const mProfile = await apiForm('POST', '/api/customer/profile', M, {
    // A groom: interests come from a profile of the other gender (SPEC §9.12).
    full_name: 'Mohan Customer', gender: 'groom', dob: '1995-04-12', community_id: COMM_A, height_cm: 172,
  });
  check('M creates her profile 201', 201, mProfile.status);
  check('… hidden until paid (SPEC §9.12)', 'hidden', mProfile.body?.profile?.status);
  const mOrder = await api('POST', `/api/customer/my-profiles/${mProfile.body?.profile?.id}/payment`, M);
  const mPaid = await api('POST', `/api/customer/payments/${mOrder.body?.payment?.id}/confirm`, M, {});
  check('… live as soon as it is paid (M is approved)', 'active', mPaid.body?.profile?.status);
  check('… M now has full access', 'full', mPaid.body?.customer?.access);

  // (c) suspended customers cannot touch their profile; the waiting screen still works.
  check('E suspends M', 200, (await api('POST', `/api/clients/${M_ID}/suspend`, E)).status);
  check('suspended: me still 200', 200, (await api('GET', '/api/customer/auth/me', M)).status);
  check('suspended: PATCH profile 403', 403, (await api('PATCH', '/api/customer/profile', M, { about: 'x' })).status);
  check('… with account_suspended', 'account_suspended', (await api('PATCH', '/api/customer/profile', M, { about: 'x' })).body?.error);
  check('suspended: add photos 403', 403, (await apiForm('POST', '/api/customer/profile/photos', M, {}, [{ buffer: TINY_JPEG, name: 'p.jpg' }])).status);
  check('E re-activates M', 200, (await api('POST', `/api/clients/${M_ID}/activate`, E)).status);
  check('active again: PATCH profile 200', 200, (await api('PATCH', '/api/customer/profile', M, { about: 'Back again' })).status);

  // (d) revoking an accepted interest also ends the auto-granted contact access of the customer's agent.
  const mInterest = await api('POST', `/api/customer/profiles/${PID}/interest`, M, { note: 'review' });
  check('M marks interest in P 201', 201, mInterest.status);
  const M_INT = mInterest.body?.interest?.id;
  check('E has no contact access yet', 'none', (await api('GET', `/api/profiles/${PID}`, E)).body?.profile?.contact_access);
  check('A accepts', 200, (await api('POST', `/api/interests/${M_INT}/accept`, A)).status);
  check('E now has contact access on P (auto-grant)', 'granted', (await api('GET', `/api/profiles/${PID}`, E)).body?.profile?.contact_access);
  check('M sees the on-request fields', true, hasProtected((await api('GET', `/api/customer/profiles/${PID}`, M)).body?.profile));
  check('A revokes', 200, (await api('POST', `/api/interests/${M_INT}/revoke`, A)).status);
  const eAfter = (await api('GET', `/api/profiles/${PID}`, E)).body?.profile;
  check('E lost contact access with the revoke', 'none', eAfter?.contact_access);
  check('… the auto-granted request reads revoked', 'revoked', eAfter?.contact_request_status);
  check('M no longer sees the on-request fields', false, hasProtected((await api('GET', `/api/customer/profiles/${PID}`, M)).body?.profile));

  // (e) bad input answers 400, never 500.
  check('non-integer page → 400', 400, (await api('GET', '/api/profiles?page=abc', A)).status);
  check('fractional limit → 400', 400, (await api('GET', '/api/customer/profiles?limit=1.5', M)).status);
  check('huge page → 400', 400, (await api('GET', '/api/profiles?page=99999999999999999999', A)).status);
  const wrongField = new FormData();
  wrongField.append('photo', new Blob([TINY_JPEG], { type: 'image/jpeg' }), 'p.jpg');
  const wrongFieldRes = await raw(`${BASE}/api/customer/profile/photos`, { method: 'POST', token: M, form: wrongField });
  check('photo under the wrong field name → 400', 400, wrongFieldRes.status);
  assertTrue('… unexpected_file', wrongFieldRes.text.includes('unexpected_file'));
  const garbage = await apiForm('POST', '/api/customer/profile/photos', M, {}, [{ buffer: Buffer.from('not a jpeg at all'), name: 'x.jpg' }]);
  check('undecodable photo → 400', 400, garbage.status);
  check('… unreadable_image', 'unreadable_image', garbage.body?.error);
  check('M still has no photos after the failed uploads', 0, (await api('GET', '/api/customer/profile', M)).body?.profile?.photos?.length);

  // (f) the registration form itself is never rate-limited (only submissions are).
  for (let i = 0; i < 3; i++) check(`registration form GET #${i + 1} 200`, 200, (await raw(REG_URL)).status);

  // ---------------------------------------------------------------- v2.2 guest mode + fee
  step('38. Guest mode, the ₹150 fee and up to 5 profiles (SPEC §9.12)');
  const gPhone = randomPhone('7');
  const gSignup = await signupCustomer({ full_name: 'Guest User', phone: gPhone });
  check('signup without an agent 201', 201, gSignup.status);
  const G = gSignup.body?.token;
  const G_ID = gSignup.body?.customer?.id;
  check('starts as a guest', 'guest', gSignup.body?.customer?.status);
  check('no agent yet', null, gSignup.body?.customer?.agent);
  check('access guest', 'guest', gSignup.body?.customer?.access);
  check('unlock checklist all open', JSON.stringify({ agent_linked: false, profile_registered: false, paid: false, approved: false }), JSON.stringify(gSignup.body?.customer?.unlock));
  check('fee is ₹150', 150, gSignup.body?.customer?.profile_fee_inr);
  check('up to 5 profiles', 5, gSignup.body?.customer?.max_profiles);
  check('payment provider mock', 'mock', gSignup.body?.customer?.payment_provider);
  check('no profiles yet', 0, gSignup.body?.customer?.profiles?.length);

  // Guest browsing: every community, cut-down cards, no name.
  const gBrowse = await api('GET', '/api/customer/profiles?limit=100&gender=bride&community_id=' + COMM_A, G);
  check('guest browse 200', 200, gBrowse.status);
  check('… access guest', 'guest', gBrowse.body?.access);
  const gRow = gBrowse.body?.profiles?.find((x) => x.id === PID);
  assertTrue('guest sees P', Boolean(gRow));
  check('guest card carries only photo, age, job, caste, package',
    'age,community,gender,id,income_text,locked,occupation_type,primary_photo_url,profession,subcaste',
    Object.keys(gRow || {}).sort().join(','));
  check('… the package', '8 LPA', gRow?.income_text);
  check('… locked', true, gRow?.locked);
  const gOther = await api('GET', `/api/customer/profiles?limit=100&community_id=${COMM_B}&gender=bride`, G);
  assertTrue("guest sees other communities too (B's bride)", gOther.body?.profiles?.some((x) => x.id === SBID));
  check('no default gender for a guest', null, (await api('GET', '/api/customer/profiles', G)).body?.gender);
  const gSearch = await api('GET', '/api/customer/profiles?q=Priya%20Kumari&limit=100', G);
  assertTrue('name search is ignored for guests (no name probing)', (gSearch.body?.total ?? 0) > 1);
  const gDetail = await api('GET', `/api/customer/profiles/${PID}`, G);
  check('guest cannot open a profile 403', 403, gDetail.status);
  check('… unlock_required', 'unlock_required', gDetail.body?.error);
  check('guest cannot mark interest', 'unlock_required', (await api('POST', `/api/customer/profiles/${PID}/interest`, G, {})).body?.error);
  check('guest cannot list interests', 403, (await api('GET', '/api/customer/interests', G)).status);
  check('guest cannot ask for an agent change', 403, (await api('POST', '/api/customer/agent-change', G, { to_agent_id: A_ID })).status);

  // Photos: a guest gets only the primary photo, watermarked.
  const twoPhotos = await apiForm('POST', '/api/profiles', A, {
    full_name: 'Two Photo Bride', gender: 'bride', dob: '1997-07-07', community_id: COMM_A, income_text: '6 LPA',
  }, [{ buffer: await samplePhoto('One'), name: '1.jpg', type: 'image/jpeg' }, { buffer: await samplePhoto('Two'), name: '2.jpg', type: 'image/jpeg' }]);
  check('A uploads a bride with two photos', 201, twoPhotos.status);
  const TP = twoPhotos.body?.profile;
  const tpPrimary = await raw(`${BASE}/api/customer/photos/${TP.photos[0].id}`, { token: G });
  check('guest gets the primary photo', 200, tpPrimary.status);
  check('… as a JPEG', 'image/jpeg', tpPrimary.headers.get('content-type'));
  check('guest cannot load the second photo', 403, (await raw(`${BASE}/api/customer/photos/${TP.photos[1].id}`, { token: G })).status);

  // Profiles need an agent first.
  const gNoAgent = await apiForm('POST', '/api/customer/my-profiles', G, { full_name: 'Too Early', gender: 'groom', dob: '1994-01-01', community_id: COMM_A });
  check('register before choosing an agent 403', 403, gNoAgent.status);
  check('… agent_required', 'agent_required', gNoAgent.body?.error);

  // Directory is open to guests; linking an agent.
  const gDir = await api('GET', '/api/customer/agents', G);
  check('guest sees the agent directory', 200, gDir.status);
  check('… nobody is current yet', false, gDir.body?.agents?.some((x) => x.is_current));
  check('unknown agent number 404', 404, (await api('POST', '/api/customer/agent', G, { agent_phone: randomPhone('9') })).status);
  check('empty body 400', 400, (await api('POST', '/api/customer/agent', G, {})).status);
  check('an account without communities (the admin) cannot take customers', 'agent_has_no_communities', (await api('POST', '/api/customer/agent', G, { agent_phone: ADMIN_PHONE })).body?.error);
  check('… and is not in the directory', false, gDir.body?.agents?.some((x) => x.phone === ADMIN_PHONE));
  const gLinkA = await api('POST', '/api/customer/agent', G, { agent_id: A_ID });
  check('link agent A by id 200', 200, gLinkA.status);
  check('… now pending', 'pending', gLinkA.body?.customer?.status);
  check('… with A', A_ID, gLinkA.body?.customer?.agent?.id);
  check('same agent again 400', 400, (await api('POST', '/api/customer/agent', G, { agent_id: A_ID })).status);
  const gLink = await api('POST', '/api/customer/agent', G, { agent_phone: cPhone });
  check('a pending customer may switch to C by phone', C_ID, gLink.body?.customer?.agent?.id);
  check('… unlock.agent_linked', true, gLink.body?.customer?.unlock?.agent_linked);
  check('C is current in the directory', C_ID, (await api('GET', '/api/customer/agents', G)).body?.agents?.find((x) => x.is_current)?.id);
  check('A no longer lists G', 0, (await api('GET', '/api/clients', A)).body?.clients?.filter((x) => x.id === G_ID).length);

  // Up to 5 profiles; always hidden until paid.
  const gp1 = await apiForm('POST', '/api/customer/my-profiles', G, {
    full_name: 'Guest Son', gender: 'groom', dob: '1994-02-02', community_id: COMM_A, income_text: '12 LPA', status: 'active',
  }, [{ buffer: TINY_JPEG, name: 's.jpg', type: 'image/jpeg' }]);
  check('first profile 201', 201, gp1.status);
  const GP1 = gp1.body?.profile?.id;
  check('… hidden (status ignored)', 'hidden', gp1.body?.profile?.status);
  check('… payment_pending', 'payment_pending', gp1.body?.profile?.visibility);
  check('… unpaid', false, gp1.body?.profile?.paid);
  check('… owned by C', C_ID, (await api('GET', `/api/profiles/${GP1}`, C)).body?.profile?.uploaded_by);
  const gpIds = [GP1];
  for (let i = 2; i <= 5; i++) {
    const r = await apiForm('POST', '/api/customer/my-profiles', G, {
      full_name: `Guest Child ${i}`, gender: i === 2 ? 'bride' : 'groom', dob: '1996-03-03', community_id: COMM_A,
    });
    check(`profile #${i} 201`, 201, r.status);
    gpIds.push(r.body?.profile?.id);
  }
  const GP2 = gpIds[1];
  const sixth = await apiForm('POST', '/api/customer/my-profiles', G, { full_name: 'One Too Many', gender: 'groom', dob: '1996-03-03', community_id: COMM_A });
  check('sixth profile 409', 409, sixth.status);
  check('… profile_limit', 'profile_limit', sixth.body?.error);
  check('delete an unpaid profile 200', 200, (await api('DELETE', `/api/customer/my-profiles/${gpIds[4]}`, G)).status);
  check('another customer cannot open my profile', 404, (await api('GET', `/api/customer/my-profiles/${GP1}`, K1)).status);
  const gList = await api('GET', '/api/customer/my-profiles', G);
  check('my-profiles lists 4', 4, gList.body?.profiles?.length);
  check('… oldest first', GP1, gList.body?.profiles?.[0]?.id);
  check('… with the fee', 150, gList.body?.profile_fee_inr);
  check('PATCH one of them 200', 'Edited', (await api('PATCH', `/api/customer/my-profiles/${GP2}`, G, { about: 'Edited' })).body?.profile?.about);
  check('v1.0 GET /customer/profile is the oldest', GP1, (await api('GET', '/api/customer/profile', G)).body?.profile?.id);
  check('agent cannot put an unpaid profile live', 409, (await api('PATCH', `/api/profiles/${GP1}`, C, { status: 'active' })).status);
  check('… payment_required', 'payment_required', (await api('PATCH', `/api/profiles/${GP1}`, C, { status: 'active' })).body?.error);
  check('agent cannot share / download an unpaid profile', 'payment_required', (await api('POST', `/api/profiles/${GP1}/share`, C, { method: 'download' })).body?.error);
  const cRowG = (await api('GET', `/api/clients/${G_ID}`, C)).body?.client;
  check('client row lists every profile', 4, cRowG?.profiles?.length);
  check('… none paid', 0, cRowG?.profiles?.filter((x) => x.paid).length);
  check('… `profile` stays the oldest', GP1, cRowG?.profile?.id);

  // The fee (mock): a failed attempt, then a success.
  const order1 = await api('POST', `/api/customer/my-profiles/${GP1}/payment`, G);
  check('checkout 201', 201, order1.status);
  check('… ₹150', 150, order1.body?.payment?.amount_inr);
  check('… 15000 paise', 15000, order1.body?.payment?.amount_paise);
  check('… INR', 'INR', order1.body?.payment?.currency);
  check('… mock provider', 'mock', order1.body?.payment?.provider);
  assertTrue('… mock order id', String(order1.body?.payment?.order_id || '').startsWith('mock_'));
  check("someone else cannot confirm my payment", 404, (await api('POST', `/api/customer/payments/${order1.body?.payment?.id}/confirm`, K1, {})).status);
  check('checkout for someone else\'s profile 404', 404, (await api('POST', `/api/customer/my-profiles/${GP1}/payment`, K1)).status);
  const failed = await api('POST', `/api/customer/payments/${order1.body?.payment?.id}/confirm`, G, { outcome: 'failure' });
  check('simulated failure 200', 200, failed.status);
  check('… payment failed', 'failed', failed.body?.payment?.status);
  check('… profile still unpaid', false, failed.body?.profile?.paid);
  check('a failed payment cannot be confirmed later', 409, (await api('POST', `/api/customer/payments/${order1.body?.payment?.id}/confirm`, G, {})).status);
  const order2 = await api('POST', `/api/customer/my-profiles/${GP1}/payment`, G);
  const paid1 = await api('POST', `/api/customer/payments/${order2.body?.payment?.id}/confirm`, G, {});
  check('payment succeeds', 'paid', paid1.body?.payment?.status);
  check('… profile paid', true, paid1.body?.profile?.paid);
  check('… awaiting the agent', 'awaiting_approval', paid1.body?.profile?.visibility);
  check('… still hidden', 'hidden', paid1.body?.profile?.status);
  check('… still guest access (not approved)', 'guest', paid1.body?.customer?.access);
  check('… checklist: paid, not approved', 'true,true,true,false', ['agent_linked', 'profile_registered', 'paid', 'approved'].map((k) => paid1.body?.customer?.unlock?.[k]).join(','));
  check('confirm again is idempotent', 'paid', (await api('POST', `/api/customer/payments/${order2.body?.payment?.id}/confirm`, G, {})).body?.payment?.status);
  check('second checkout for a paid profile 409', 409, (await api('POST', `/api/customer/my-profiles/${GP1}/payment`, G)).status);
  check('a paid profile cannot be deleted', 409, (await api('DELETE', `/api/customer/my-profiles/${GP1}`, G)).status);
  check('the hidden paid profile is invisible to A', 404, (await api('GET', `/api/profiles/${GP1}`, A)).status);
  check('C sees it paid on the client row', true, (await api('GET', `/api/clients/${G_ID}`, C)).body?.client?.profiles?.find((x) => x.id === GP1)?.paid);

  // Approval: paid profiles go live, unpaid ones stay hidden.
  check('C approves G', 200, (await api('POST', `/api/clients/${G_ID}/approve`, C)).status);
  const gMe = (await api('GET', '/api/customer/auth/me', G)).body?.customer;
  check('G has full access now', 'full', gMe?.access);
  check('paid profile live', 'live', gMe?.profiles?.find((x) => x.id === GP1)?.visibility);
  check('unpaid profile still waiting for payment', 'payment_pending', gMe?.profiles?.find((x) => x.id === GP2)?.visibility);
  check('A (same community) sees the paid profile now', 200, (await api('GET', `/api/profiles/${GP1}`, A)).status);
  check('A cannot see the unpaid one', 404, (await api('GET', `/api/profiles/${GP2}`, A)).status);
  const o3 = await api('POST', `/api/customer/my-profiles/${GP2}/payment`, G);
  check('paying after approval puts it live at once', 'live', (await api('POST', `/api/customer/payments/${o3.body?.payment?.id}/confirm`, G, {})).body?.profile?.visibility);

  // Full browsing: agent's communities, names, default gender from the oldest paid profile (a groom).
  const gFull = await api('GET', '/api/customer/profiles?limit=100', G);
  check('full browse 200', 200, gFull.status);
  check('… access full', 'full', gFull.body?.access);
  check('… defaults to brides', 'bride', gFull.body?.gender);
  check('… rows are not locked and carry names', true, gFull.body?.profiles?.length > 0 && gFull.body.profiles.every((x) => !x.locked && typeof x.full_name === 'string'));
  check('… never my own profiles', 0, gFull.body?.profiles?.filter((x) => gpIds.includes(x.id)).length);
  check('full access: the second photo loads', 200, (await raw(`${BASE}/api/customer/photos/${TP.photos[1].id}`, { token: G })).status);
  check('full access: detail 200', 200, (await api('GET', `/api/customer/profiles/${PID}`, G)).status);

  // Interests on behalf of one of several profiles.
  const gInt = await api('POST', `/api/customer/profiles/${PID}/interest`, G, {});
  check('interest defaults to my only live groom', 201, gInt.status);
  check('… from_profile is the groom', GP1, gInt.body?.interest?.from_profile?.id);
  const aSees = (await api('GET', '/api/interests?box=received', A)).body?.interests?.find((x) => x.id === gInt.body?.interest?.id);
  check("uploader sees which of G's profiles is interested", GP1, aSees?.customer_profile?.id);
  // A second live groom makes the default ambiguous.
  const gp3 = gpIds[2];
  const o4 = await api('POST', `/api/customer/my-profiles/${gp3}/payment`, G);
  await api('POST', `/api/customer/payments/${o4.body?.payment?.id}/confirm`, G, {});
  const amb = await api('POST', `/api/customer/profiles/${TP.id}/interest`, G, {});
  check('two live grooms → 400', 400, amb.status);
  check('… from_profile_required', 'from_profile_required', amb.body?.error);
  check('a bride cannot be interested in a bride', 'invalid_from_profile', (await api('POST', `/api/customer/profiles/${TP.id}/interest`, G, { from_profile_id: GP2 })).body?.error);
  const chosen = await api('POST', `/api/customer/profiles/${TP.id}/interest`, G, { from_profile_id: gp3 });
  check('explicit from_profile_id 201', 201, chosen.status);
  check('… recorded', gp3, chosen.body?.interest?.from_profile?.id);
  check('my interests list both', 2, (await api('GET', '/api/customer/interests', G)).body?.interests?.filter((x) => [PID, TP.id].includes(x.profile?.id)).length);

  // Admin: guests are listed; giving a guest an agent makes them pending.
  const g2 = await signupCustomer({ full_name: 'Second Guest', phone: randomPhone('7') });
  const G2_ID = g2.body?.customer?.id;
  const adminGuests = await api('GET', '/api/admin/customers?status=guest', ADMIN);
  check('admin lists guests', 1, adminGuests.body?.customers?.filter((x) => x.id === G2_ID).length);
  check('… with no agent', null, adminGuests.body?.customers?.find((x) => x.id === G2_ID)?.agent_id);
  check('… agent is null (not an empty object)', null, adminGuests.body?.customers?.find((x) => x.id === G2_ID)?.agent);
  check('admin cannot activate a guest', 409, (await api('POST', `/api/admin/customers/${G2_ID}/activate`, ADMIN)).status);
  const g2Reassigned = await api('PUT', `/api/admin/customers/${G2_ID}/agent`, ADMIN, { agent_id: C_ID });
  check('admin gives the guest an agent', 200, g2Reassigned.status);
  check('… now pending', 'pending', g2Reassigned.body?.customer?.status);
  const stats22 = (await api('GET', '/api/admin/stats', ADMIN)).body?.stats;
  assertTrue('stats count paid registrations', (stats22?.paid_registrations ?? 0) >= 3);
  assertTrue('stats carry guest_customers', typeof stats22?.guest_customers === 'number');
  check('v1.0 signup with agent_phone still starts pending', 'pending', (await signupCustomer({ full_name: 'Old App', phone: randomPhone('7'), agent_phone: cPhone })).body?.customer?.status);

  // ---------------------------------------------------------------- v2.3
  step('39. Guest filters, delete requests for paid profiles, cash payments (SPEC §9.13)');
  const G2 = g2.body?.token;
  const g2Place = await api('GET', '/api/customer/profiles?city=Hyderabad&limit=100', G2);
  check('guest place filter 200', 200, g2Place.status);
  check('… still guest cards', 'guest', g2Place.body?.access);
  assertTrue('… the place filter applies (fewer rows than unfiltered)', (g2Place.body?.total ?? 0) < ((await api('GET', '/api/customer/profiles?limit=1', G2)).body?.total ?? 0));
  assertTrue('… P (native place Hyderabad) matches', g2Place.body?.profiles?.some((x) => x.id === PID));
  check('… without revealing the place', false, g2Place.body?.profiles?.some((x) => 'city' in x || 'work_place' in x));

  // Cash payment recorded by the agent.
  const GP4 = gpIds[3];
  check('another agent cannot mark it paid', 403, (await api('POST', `/api/clients/${G_ID}/profiles/${GP4}/mark-paid`, A, {})).status);
  check("a profile of someone else's client 404", 404, (await api('POST', `/api/clients/${G_ID}/profiles/${PID}/mark-paid`, C, {})).status);
  const cash = await api('POST', `/api/clients/${G_ID}/profiles/${GP4}/mark-paid`, C, { note: 'Cash at office' });
  check('C marks it paid in cash 200', 200, cash.status);
  check('… client row shows it paid', true, cash.body?.client?.profiles?.find((x) => x.id === GP4)?.paid);
  check('… live at once (G is active)', 'live', (await api('GET', `/api/customer/my-profiles/${GP4}`, G)).body?.profile?.visibility);
  check('mark paid twice 409', 409, (await api('POST', `/api/clients/${G_ID}/profiles/${GP4}/mark-paid`, C, {})).status);

  // Deleting a paid profile needs the agent.
  check('customer cannot delete a paid profile directly', 'approval_required', (await api('DELETE', `/api/customer/my-profiles/${GP2}`, G)).body?.error);
  const dr1 = await api('POST', `/api/customer/my-profiles/${GP2}/delete-request`, G, { reason: 'Married elsewhere' });
  check('delete request 201', 201, dr1.status);
  check('… pending', 'pending', dr1.body?.delete_request?.status);
  check('second request 409', 409, (await api('POST', `/api/customer/my-profiles/${GP2}/delete-request`, G, {})).status);
  check('me.profiles carries delete_request_id', dr1.body?.delete_request?.id, (await api('GET', '/api/customer/auth/me', G)).body?.customer?.profiles?.find((x) => x.id === GP2)?.delete_request_id);
  check('own view shows the pending request', dr1.body?.delete_request?.id, (await api('GET', `/api/customer/my-profiles/${GP2}`, G)).body?.profile?.delete_request?.id);
  const cN = (await api('GET', '/api/notifications', C)).body;
  assertTrue('C is notified', cN?.items?.some((i) => i.type === 'profile_delete_requested' && i.id === dr1.body?.delete_request?.id));
  assertTrue('… counted in delete_requests_inbox', (cN?.counts?.delete_requests_inbox ?? 0) >= 1);
  check('client row flags the profile', dr1.body?.delete_request?.id, (await api('GET', `/api/clients/${G_ID}`, C)).body?.client?.profiles?.find((x) => x.id === GP2)?.delete_request_id);
  check('client detail lists it', 1, (await api('GET', `/api/clients/${G_ID}`, C)).body?.client?.delete_requests?.filter((x) => x.id === dr1.body?.delete_request?.id).length);
  const cList = await api('GET', '/api/clients/delete-requests', C);
  check('C lists it', 1, cList.body?.delete_requests?.filter((x) => x.id === dr1.body?.delete_request?.id).length);
  check('… with the reason', 'Married elsewhere', cList.body?.delete_requests?.find((x) => x.id === dr1.body?.delete_request?.id)?.reason);
  check('A does not list it', 0, (await api('GET', '/api/clients/delete-requests', A)).body?.delete_requests?.filter((x) => x.id === dr1.body?.delete_request?.id).length);
  check('A cannot approve it', 403, (await api('POST', `/api/clients/delete-requests/${dr1.body?.delete_request?.id}/approve`, A)).status);
  check('C rejects 200', 'rejected', (await api('POST', `/api/clients/delete-requests/${dr1.body?.delete_request?.id}/reject`, C)).body?.delete_request?.status);
  check('profile still there', 200, (await api('GET', `/api/customer/my-profiles/${GP2}`, G)).status);
  const dr2 = await api('POST', `/api/customer/my-profiles/${GP2}/delete-request`, G, {});
  check('customer cancels a new request', 'cancelled', (await api('POST', `/api/customer/delete-requests/${dr2.body?.delete_request?.id}/cancel`, G)).body?.delete_request?.status);
  const dr3 = await api('POST', `/api/customer/my-profiles/${GP2}/delete-request`, G, {});
  const approvedDel = await api('POST', `/api/clients/delete-requests/${dr3.body?.delete_request?.id}/approve`, ADMIN);
  check('admin can approve 200', 200, approvedDel.status);
  check('… approved', 'approved', approvedDel.body?.delete_request?.status);
  check('… profile name kept', 'Guest Child 2', approvedDel.body?.delete_request?.profile_name);
  check('… profile gone', 404, (await api('GET', `/api/customer/my-profiles/${GP2}`, G)).status);
  check('… gone for agents too', 404, (await api('GET', `/api/profiles/${GP2}`, C)).status);
  check('approve again 409', 409, (await api('POST', `/api/clients/delete-requests/${dr3.body?.delete_request?.id}/approve`, C)).status);
  const unpaidNew = await apiForm('POST', '/api/customer/my-profiles', G, { full_name: 'Unpaid New', gender: 'groom', dob: '1996-03-03', community_id: COMM_A });
  check('delete request on an unpaid profile → 400 not_paid', 'not_paid', (await api('POST', `/api/customer/my-profiles/${unpaidNew.body?.profile?.id}/delete-request`, G, {})).body?.error);

  // ---------------------------------------------------------------- v2.5
  step('40. Gandharva notifications (SPEC §9.15)');
  check('agent token refused', 401, (await api('GET', '/api/customer/notifications', C)).status);
  const gNotif = await api('GET', '/api/customer/notifications', G);
  check('customer notifications 200', 200, gNotif.status);
  const gItems = gNotif.body?.items ?? [];
  const hasNotif = (type, pred = () => true) => gItems.some((i) => i.type === type && pred(i));
  assertTrue('account_approved', hasNotif('account_approved'));
  assertTrue('payment_due for the unpaid profile', hasNotif('payment_due', (i) => i.my_profile_id === unpaidNew.body?.profile?.id && i.group === 'action'));
  check('action_count = action items', gItems.filter((i) => i.group === 'action').length, gNotif.body?.action_count);
  assertTrue('payment_received for the cash payment (says cash)', hasNotif('payment_received', (i) => i.my_profile_id === GP4 && /cash/.test(i.body)));
  check('waived payments are not listed', false, hasNotif('payment_received', (i) => i.body.startsWith('₹0')));
  assertTrue('delete_request_approved', hasNotif('delete_request_approved', (i) => /Guest Child 2/.test(i.body)));
  assertTrue('delete_request_rejected', hasNotif('delete_request_rejected'));
  check('action items come first', true, gItems.findIndex((i) => i.group === 'update') >= gNotif.body?.action_count);
  check('never names another profile\'s uploader (Agent A)', false, JSON.stringify(gItems).includes('Agent A'));
  // An accepted interest shows up (and would warn before it ends).
  const gAccepted = await api('POST', `/api/interests/${gInt.body?.interest?.id}/accept`, A);
  check('A accepts G\'s interest', 200, gAccepted.status);
  const gNotif2 = (await api('GET', '/api/customer/notifications', G)).body;
  assertTrue('interest_accepted with the profile', gNotif2?.items?.some((i) => i.type === 'interest_accepted' && i.profile_id === PID));
  // A guest gets an empty but valid feed.
  const g3Cust = await signupCustomer({ full_name: 'Quiet Guest', phone: randomPhone('7') });
  const g3Notif = await api('GET', '/api/customer/notifications', g3Cust.body?.token);
  check('guest feed 200', 200, g3Notif.status);
  check('… nothing yet', 0, g3Notif.body?.items?.length);
  check('… action_count 0', 0, g3Notif.body?.action_count);
  // A rejected customer is told.
  const rjCust = await signupCustomer({ full_name: 'Rejected Later', phone: randomPhone('7'), agent_phone: cPhone });
  await api('POST', `/api/clients/${rjCust.body?.customer?.id}/reject`, C);
  assertTrue('account_rejected', (await api('GET', '/api/customer/notifications', rjCust.body?.token)).body?.items?.some((i) => i.type === 'account_rejected'));

  // ---------------------------------------------------------------- v2.6 push
  step('41. Push notifications (SPEC §9.16) — needs PUSH_PROVIDER=log on the API');
  const pcfg = await api('GET', '/api/push/config?app=mediator');
  check('push config is public 200', 200, pcfg.status);
  if (!pcfg.body?.enabled) {
    console.log('  (push is off on this API — start it with PUSH_PROVIDER=log to run this step)');
  } else {
    check('… gandharva config too', true, (await api('GET', '/api/push/config?app=gandharva')).body?.enabled);
    check('bad app 400', 400, (await api('GET', '/api/push/config?app=other')).status);
    const cTok = `smoke-c-${Date.now()}-token`;
    const gTok = `smoke-g-${Date.now()}-token`;
    check('register needs auth', 401, (await api('POST', '/api/push/devices', null, { token: cTok })).status);
    check('customer token refused on the agent route', 401, (await api('POST', '/api/push/devices', G, { token: gTok })).status);
    check('agent C registers 201', 201, (await api('POST', '/api/push/devices', C, { token: cTok })).status);
    check('customer G registers 201', 201, (await api('POST', '/api/customer/push/devices', G, { token: gTok })).status);
    check('re-register is idempotent', 201, (await api('POST', '/api/push/devices', C, { token: cTok })).status);
    check('short token 400', 400, (await api('POST', '/api/push/devices', C, { token: 'x' })).status);
    const outFor = async (tok) => (await api('GET', '/api/admin/push/outbox', ADMIN)).body?.pushes?.filter((p) => p.token === tok) ?? [];
    await new Promise((r) => setTimeout(r, 1100));
    check('first pass 200', 200, (await api('POST', '/api/admin/push/run', ADMIN)).status);
    check('no backlog pushed to a new device (C)', 0, (await outFor(cTok)).length);
    check('no backlog pushed to a new device (G)', 0, (await outFor(gTok)).length);
    // New events after registration.
    const pushCust = await signupCustomer({ full_name: 'Push Client', phone: randomPhone('7'), agent_phone: cPhone });
    check('a new client for C', 201, pushCust.status);
    const pushProf = await apiForm('POST', '/api/customer/my-profiles', G, { full_name: 'Push Profile', gender: 'groom', dob: '1996-03-03', community_id: COMM_A });
    check('cash payment recorded for G', 200, (await api('POST', `/api/clients/${G_ID}/profiles/${pushProf.body?.profile?.id}/mark-paid`, C, {})).status);
    await new Promise((r) => setTimeout(r, 1100));
    const pass2 = await api('POST', '/api/admin/push/run', ADMIN);
    assertTrue('second pass sent something', (pass2.body?.sent ?? 0) >= 2, JSON.stringify(pass2.body));
    const cPushes = await outFor(cTok);
    const cp = cPushes.find((p) => p.data?.type === 'client_pending');
    assertTrue('C got a client_pending push', Boolean(cp));
    check('… with the customer id as a string', String(pushCust.body?.customer?.id), cp?.data?.customer_id);
    check('… for the mediator app', 'mediator', cp?.data?.app);
    const gp = (await outFor(gTok)).find((p) => p.data?.type === 'payment_received');
    assertTrue('G got a payment_received push', Boolean(gp));
    check('… naming the profile', true, /Push Profile/.test(gp?.body ?? ''));
    check('payment_due is never pushed', 0, (await outFor(gTok)).filter((p) => p.data?.type === 'payment_due').length);
    await api('POST', '/api/admin/push/run', ADMIN);
    check('no duplicates on the next pass', cPushes.length, (await outFor(cTok)).length);
    check('remove device 200', 200, (await api('POST', '/api/push/devices/remove', C, { token: cTok })).status);
    await signupCustomer({ full_name: 'After Logout', phone: randomPhone('7'), agent_phone: cPhone });
    await new Promise((r) => setTimeout(r, 1100));
    await api('POST', '/api/admin/push/run', ADMIN);
    check('nothing pushed after logout', cPushes.length, (await outFor(cTok)).length);
    check('customer removes theirs 200', 200, (await api('POST', '/api/customer/push/devices/remove', G, { token: gTok })).status);
    check('push run is admin-only', 403, (await api('POST', '/api/admin/push/run', C)).status);
  }

  // ---------------------------------------------------------------- summary
  const total = pass + failures.length;
  console.log(`\n${bold(`====== ${pass}/${total} passed ======`)}`);
  if (failures.length) {
    console.log(red(`\n${failures.length} failing:`));
    for (const f of failures) console.log(red(`  - ${f}`));
    process.exit(1);
  }
  console.log(green('All business rules verified.\n'));
}

main().catch((e) => {
  console.error(red(`\nSmoke test crashed: ${e.stack || e.message}`));
  process.exit(1);
});
