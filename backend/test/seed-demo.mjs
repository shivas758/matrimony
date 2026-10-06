/**
 * Seeds realistic demo data so the Flutter app has something to render.
 * Dev only — talks to the API exactly like the app does.
 *
 *   node test/seed-demo.mjs
 *   BASE=http://localhost:3000 node test/seed-demo.mjs
 *
 * Creates two communities, three agents (password: demo1234), ~12 profiles
 * with generated placeholder photos, and two Gandharva customers per agent
 * (one active with a profile, one still pending) so both apps have data.
 * Needs the mock OTP provider (the default) — signups go through the OTP
 * round trip like the apps do; set OTP_CODE if the mock code was changed.
 */

import sharp from 'sharp';

const BASE = (process.env.BASE || 'http://localhost:3000').replace(/\/+$/, '');
const ADMIN_PHONE = process.env.ADMIN_PHONE || '9999999999';
const ADMIN_PASS = process.env.ADMIN_PASS || 'ChangeMe@123';
const DEMO_PASS = 'demo1234';
const OTP_CODE = process.env.OTP_CODE || '123456';
// The credential endpoints allow 50 calls per 15 min per client address; the
// API trusts one proxy hop, so each run presents its own address (see smoke.mjs).
const RUN_IP = `10.${1 + Math.floor(Math.random() * 254)}.${Math.floor(Math.random() * 255)}.${1 + Math.floor(Math.random() * 254)}`;

async function api(method, path, token, body) {
  const headers = { 'X-Forwarded-For': RUN_IP };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  try {
    return { status: res.status, body: JSON.parse(text) };
  } catch {
    return { status: res.status, body: text };
  }
}

/** A plain coloured card with initials — stands in for a real photo. */
async function placeholderPhoto(name, hue) {
  const initials = name.split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase();
  const svg = `<svg width="900" height="900" xmlns="http://www.w3.org/2000/svg">
      <rect width="900" height="900" fill="hsl(${hue}, 42%, 78%)"/>
      <circle cx="450" cy="380" r="190" fill="hsl(${hue}, 40%, 88%)"/>
      <text x="450" y="380" font-family="DejaVu Sans, Arial, sans-serif" font-size="150"
            fill="hsl(${hue}, 45%, 32%)" text-anchor="middle" dominant-baseline="central">${initials}</text>
      <text x="450" y="700" font-family="DejaVu Sans, Arial, sans-serif" font-size="52"
            fill="hsl(${hue}, 40%, 30%)" text-anchor="middle">${name}</text>
    </svg>`;
  return sharp(Buffer.from(svg)).jpeg({ quality: 85 }).toBuffer();
}

async function createProfile(token, fields, photoBuf, path = '/api/profiles') {
  const form = new FormData();
  for (const [k, v] of Object.entries(fields)) if (v != null) form.append(k, String(v));
  if (photoBuf) form.append('photos', new Blob([photoBuf], { type: 'image/jpeg' }), 'photo.jpg');
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'X-Forwarded-For': RUN_IP },
    body: form,
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}

/** OTP round trip (SPEC §9.1): send → verify. Returns the verify response, or null when throttled. */
async function otpVerify(prefix, phone) {
  const send = await api('POST', `${prefix}/otp/send`, null, { phone });
  if (send.status === 429) {
    console.warn(`  ${phone}: OTP throttled (${send.body?.error}) — try again in a minute`);
    return null;
  }
  if (send.status !== 200) return send;
  return api('POST', `${prefix}/otp/verify`, null, { phone, code: send.body?.mock_code || OTP_CODE });
}

/** Agent signup with the OTP proof; an existing number (409 at send) logs in instead. */
async function signupOrLoginAgent(spec) {
  const send = await api('POST', '/api/auth/otp/send', null, { phone: spec.phone });
  if (send.status === 409) {
    console.log(`  ${spec.full_name} already existed — reusing.`);
    return api('POST', '/api/auth/login', null, { phone: spec.phone, password: DEMO_PASS });
  }
  if (send.status !== 200) return send;
  const verify = await api('POST', '/api/auth/otp/verify', null, { phone: spec.phone, code: send.body?.mock_code || OTP_CODE });
  return api('POST', '/api/auth/signup', null, {
    full_name: spec.full_name,
    phone: spec.phone,
    password: DEMO_PASS,
    agency_name: spec.agency,
    community_ids: spec.comm,
    phone_verification_token: verify.body?.verification_token,
  });
}

// [name, dob, height_cm, native city, state, income, work place, weight, gothram, nri country | null]
const BRIDES = [
  ['Priya Kumari', '1998-04-12', 160, 'Nalgonda', 'Telangana', '8 LPA', 'Hyderabad', 52, 'Bharadwaja', null],
  ['Anjali Reddy', '1996-11-03', 158, 'Warangal', 'Telangana', '6 LPA', 'Hyderabad', 55, 'Kashyapa', null],
  ['Sneha Rao', '1999-02-21', 163, 'Vijayawada', 'Andhra Pradesh', '$90k', 'Dallas', 54, 'Vasishta', 'United States'],
  ['Divya Sharma', '1995-07-30', 155, 'Guntur', 'Andhra Pradesh', '15 LPA', 'Bengaluru', 50, 'Atreya', null],
  ['Lakshmi Nair', '1997-09-15', 161, 'Chennai', 'Tamil Nadu', '9 LPA', 'Chennai', 56, 'Gautama', null],
  ['Meena Patel', '2000-01-08', 157, 'Khammam', 'Telangana', '£45k', 'London', 51, 'Kaundinya', 'United Kingdom'],
];

const GROOMS = [
  ['Ravi Teja', '1994-03-19', 175, 'Karimnagar', 'Telangana', '18 LPA', 'Hyderabad', 72, 'Bharadwaja', null],
  ['Karthik Menon', '1993-08-25', 178, 'Kochi', 'Kerala', '24 LPA', 'Bengaluru', 75, 'Vasishta', null],
  ['Arjun Varma', '1995-12-11', 172, 'Rajahmundry', 'Andhra Pradesh', 'AUD 110k', 'Sydney', 70, 'Kashyapa', 'Australia'],
  ['Suresh Babu', '1992-05-06', 170, 'Vizag', 'Andhra Pradesh', '10 LPA', 'Vizag', 68, 'Atreya', null],
  ['Naveen Kumar', '1996-10-02', 176, 'Nizamabad', 'Telangana', '20 LPA', 'Hyderabad', 74, 'Gautama', null],
  ['Vikram Shetty', '1991-06-28', 180, 'Mangalore', 'Karnataka', '€80k', 'Munich', 78, 'Kaundinya', 'Germany'],
];

const ABOUT = [
  'Family oriented, believes in traditional values with a modern outlook.',
  'Working professional, enjoys travel and classical music.',
  'Simple, hardworking and close to family. Looking for a like-minded partner.',
  'Cheerful and independent. Enjoys cooking and reading.',
];

const pick = (arr, i) => arr[i % arr.length];

// Two Gandharva customers per demo agent: [name, gender, dob, height, native city]
// — the first gets a profile and is approved, the second stays pending.
const CUSTOMERS = [
  ['Harini Reddy', 'bride', '1998-06-14', 159, 'Nalgonda'],
  ['Mahesh Babu', 'groom', '1994-02-02', 174, 'Warangal'],
];

async function main() {
  const login = await api('POST', '/api/auth/login', null, { phone: ADMIN_PHONE, password: ADMIN_PASS });
  if (login.status !== 200) {
    console.error(`Admin login failed (${login.status}). Is the API running at ${BASE}?`);
    process.exit(1);
  }
  const admin = login.body.token;
  console.log('Logged in as admin.');

  // Communities the demo agents will belong to.
  const wanted = ['Kamma', 'Reddy'];
  const masters = (await api('GET', '/api/masters')).body;
  const communityIds = [];
  for (const name of wanted) {
    const existing = masters.communities.find((c) => c.name === name);
    if (existing) {
      communityIds.push(existing.id);
      continue;
    }
    const added = await api('POST', '/api/admin/masters/communities', admin, { name });
    if (added.status === 201) communityIds.push(added.body.row.id);
    else console.warn(`  could not add community ${name}: ${added.status}`);
  }
  console.log(`Communities ready: ${wanted.join(', ')}`);

  // Three demo agents: two in Kamma, one in Reddy.
  const agentSpecs = [
    { full_name: 'Suresh Bureau', phone: '9000000001', agency: 'Sri Sai Marriage Bureau', comm: [communityIds[0]] },
    { full_name: 'Padma Bureau', phone: '9000000002', agency: 'Padma Matrimony', comm: [communityIds[0]] },
    { full_name: 'Kiran Bureau', phone: '9000000003', agency: 'Kiran Alliances', comm: [communityIds[1]] },
  ];

  const tokens = [];
  for (const spec of agentSpecs) {
    const res = await signupOrLoginAgent(spec);
    if (res.status !== 200 && res.status !== 201) {
      console.warn(`  could not create ${spec.full_name}: ${res.status} ${JSON.stringify(res.body)}`);
      continue;
    }
    await api('POST', `/api/admin/agents/${res.body.agent.id}/activate`, admin);
    await api('PATCH', '/api/my/account', res.body.token, { city: pick(['Hyderabad', 'Vijayawada', 'Guntur'], tokens.length) });
    tokens.push({ token: res.body.token, ...spec });
  }
  console.log(`Agents ready (password ${DEMO_PASS}): ${tokens.map((t) => t.phone).join(', ')}`);

  const m = (await api('GET', '/api/masters')).body;
  const india = m.countries.find((c) => c.name === 'India');

  let made = 0;
  const rows = [
    ...BRIDES.map((r) => ['bride', ...r]),
    ...GROOMS.map((r) => ['groom', ...r]),
  ];

  for (let i = 0; i < rows.length; i++) {
    const [gender, name, dob, height, city, state, income, workPlace, weight, gothram, nriCountry] = rows[i];
    const agent = pick(tokens, i);
    if (!agent) break;
    const photo = await placeholderPhoto(name, (i * 47) % 360);
    const country = nriCountry ? m.countries.find((c) => c.name === nriCountry) : null;
    const surname = name.split(' ').slice(-1)[0];
    const res = await createProfile(
      agent.token,
      {
        full_name: name,
        gender,
        dob,
        height_cm: height,
        weight_kg: weight,
        complexion_id: pick(m.complexions, i).id,
        gothram,
        community_id: agent.comm[0],
        education_id: pick(m.educations, i + 4).id,
        education_details: pick(['Osmania University', 'JNTU Hyderabad', 'Andhra University', 'Anna University'], i),
        profession_id: pick(m.professions, i).id,
        profession_details: pick(['Team lead, 6 years experience', 'Own business since 2019', 'Working since 2017'], i),
        work_place: workPlace,
        work_country_id: country?.id ?? india?.id,
        nationality_id: india?.id,
        occupation_type_id: pick(m.occupation_types ?? [{}], i).id,
        education_levels: JSON.stringify([
          { level: '10th', details: 'SSC', country_id: india?.id },
          { level: 'graduation', details: pick(['B.Tech', 'B.Com', 'B.Sc', 'BBA'], i), country_id: india?.id },
        ]),
        is_nri: Boolean(country),
        nri_country_id: country?.id,
        nri_place: country ? workPlace : null,
        marital_status_id: m.marital_statuses[0].id,
        zodiac_id: pick(m.zodiac_signs, i).id,
        nakshatram_id: pick(m.nakshatrams, i * 3).id,
        birth_time: pick(['04:35', '10:15', '22:40', '13:05'], i),
        birth_place: city,
        city,
        state,
        income_text: income,
        about: pick(ABOUT, i),
        family_details: 'Father retired government employee, mother homemaker. One sibling, married.',
        religion_id: m.religions?.[0]?.id,
        mother_tongue_id: m.languages?.[0]?.id,
        known_language_ids: [m.languages?.[0]?.id, m.languages?.[1]?.id, m.languages?.[2]?.id].filter(Boolean).join(','),
        food_habit_id: pick(m.food_habits ?? [{}], i).id,
        has_siblings: 'true',
        siblings_count: 1,
        siblings_details: pick(['One elder brother, married, settled in Hyderabad.', 'One younger sister, studying.'], i),
        father_name: `Rama ${surname}`,
        father_phone: `98${String(76543000 + i * 137).padStart(8, '0')}`,
        mother_name: `Sita ${surname}`,
        mother_phone: `97${String(76543000 + i * 131).padStart(8, '0')}`,
        contact_name: `${name.split(' ')[0]}'s father`,
        contact_phone: `98${String(76543000 + i * 137).padStart(8, '0')}`,
      },
      photo,
    );
    if (res.status === 201) made++;
    else console.warn(`  ${name}: ${res.status} ${JSON.stringify(res.body).slice(0, 160)}`);
  }

  console.log(`\nSeeded ${made} profiles.`);

  // ---- Gandharva customers (SPEC §9): phone + OTP, attached to a demo agent.
  const customerPhones = [];
  for (let a = 0; a < tokens.length; a++) {
    const agent = tokens[a];
    for (let c = 0; c < CUSTOMERS.length; c++) {
      const [name, gender, dob, height, city] = CUSTOMERS[c];
      const phone = `90000001${a + 1}${c + 1}`;
      const verify = await otpVerify('/api/customer/auth', phone);
      if (!verify) continue;
      let token = verify.body?.token;
      let customerId = verify.body?.customer?.id;
      if (verify.body?.new) {
        const signup = await api('POST', '/api/customer/auth/signup', null, {
          full_name: name, phone, agent_phone: agent.phone, phone_verification_token: verify.body.verification_token,
        });
        if (signup.status !== 201) {
          console.warn(`  customer ${phone}: ${signup.status} ${JSON.stringify(signup.body).slice(0, 160)}`);
          continue;
        }
        token = signup.body.token;
        customerId = signup.body.customer.id;
      }
      if (!token) {
        console.warn(`  customer ${phone}: ${verify.status} ${JSON.stringify(verify.body).slice(0, 160)}`);
        continue;
      }
      if (c === 0) {
        // First customer: fills in their profile, then the agent approves them
        // (which flips the hidden profile to active — SPEC §9.2).
        const own = await api('GET', '/api/customer/profile', token);
        if (own.status === 404) {
          const res = await createProfile(
            token,
            {
              full_name: name, gender, dob, height_cm: height, community_id: agent.comm[0],
              education_id: pick(m.educations, c + 2).id, profession_id: pick(m.professions, c + 1).id,
              marital_status_id: m.marital_statuses[0].id, religion_id: m.religions?.[0]?.id,
              mother_tongue_id: m.languages?.[0]?.id, nationality_id: india?.id, work_country_id: india?.id,
              work_place: 'Hyderabad', city, state: 'Telangana', income_text: '7 LPA',
              father_name: `Rama ${name.split(' ').slice(-1)[0]}`, father_phone: `98${String(70000000 + a * 100 + c).padStart(8, '0')}`,
              contact_name: 'Father', contact_phone: `98${String(70000000 + a * 100 + c).padStart(8, '0')}`,
              about: pick(ABOUT, a + c),
            },
            await placeholderPhoto(name, (a * 61 + 200) % 360),
            '/api/customer/profile',
          );
          if (res.status !== 201) console.warn(`  ${name}: profile ${res.status} ${JSON.stringify(res.body).slice(0, 160)}`);
        }
        // Pay the registration fee (mock provider) so approval puts it live (SPEC §9.12).
        const mine = await api('GET', '/api/customer/profile', token);
        if (mine.body?.profile && !mine.body.profile.paid) {
          const order = await api('POST', `/api/customer/my-profiles/${mine.body.profile.id}/payment`, token);
          if (order.status === 201) await api('POST', `/api/customer/payments/${order.body.payment.id}/confirm`, token, {});
          else console.warn(`  ${name}: payment ${order.status} ${JSON.stringify(order.body).slice(0, 160)}`);
        }
        await api('POST', `/api/clients/${customerId}/approve`, agent.token); // 409 when already active
      }
      customerPhones.push(`${phone} (${agent.full_name}, ${c === 0 ? 'active' : 'pending'})`);
    }
  }
  console.log(`\nCustomers ready (Gandharva, OTP ${OTP_CODE}):\n  ${customerPhones.join('\n  ')}`);
  console.log(`\nDemo logins: 9000000001 / 9000000002 / 9000000003  password: ${DEMO_PASS}`);
  console.log(`Admin: ${ADMIN_PHONE} / ${ADMIN_PASS}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
