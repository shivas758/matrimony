// Public website at the domain root — SPEC §9.19 E. The pages a payment gateway
// (Razorpay) reviews: home with the app downloads, about, contact, pricing,
// terms, privacy, refunds, shipping. No login, no tracking, no data from the
// database — only the fee and the business identity from config.
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../lib/config.js';
import { escapeXml as esc } from '../lib/photos.js';
import { phoneSchema } from '../lib/validate.js';
import { createDeletionRequest } from '../lib/accountDeletion.js';

export const siteRouter = Router();

const LOGO = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'site', 'logo.png');
const DOWNLOADS = {
  'wedbook-matrimony.apk': 'Wedbook Matrimony',
  'wedbook-agent.apk': 'Wedbook Agent',
};
const UPDATED = '13 November 2026';

const fee = () => config.payments.profileFeeInr;
const rupees = (n) => `₹${Number(n).toLocaleString('en-IN')}`;
const biz = () => config.site.businessName;

const NAV = [
  ['/', 'Home'],
  ['/pricing', 'Pricing'],
  ['/about', 'About us'],
  ['/contact', 'Contact us'],
];
const POLICIES = [
  ['/about', 'About us'],
  ['/contact', 'Contact us'],
  ['/pricing', 'Pricing'],
  ['/terms', 'Terms & Conditions'],
  ['/privacy', 'Privacy Policy'],
  ['/refunds', 'Refund & Cancellation'],
  ['/shipping', 'Shipping & Delivery'],
  ['/delete-account', 'Delete account'],
];

/** Contact lines that are configured, as HTML list items. */
function contactItems() {
  const s = config.site;
  return [
    `<li><b>${esc(s.businessName)}</b></li>`,
    s.address ? `<li>${esc(s.address).replace(/\n/g, '<br>')}</li>` : '',
    s.phone ? `<li>Phone / WhatsApp: <a href="tel:+91${esc(s.phone)}">+91 ${esc(s.phone)}</a></li>` : '',
    s.email ? `<li>Email: <a href="mailto:${esc(s.email)}">${esc(s.email)}</a></li>` : '',
  ].join('');
}

function layout(route, title, body) {
  const nav = NAV.map(([href, label]) => `<a href="${href}"${href === route ? ' class="on"' : ''}>${label}</a>`).join('');
  const foot = POLICIES.map(([href, label]) => `<a href="${href}">${label}</a>`).join('');
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#540729">
<title>${esc(title)} — Wedbook Matrimony</title>
<meta name="description" content="Wedbook Matrimony — matrimony profiles through trusted marriage bureau agents. Registration fee ${rupees(fee())} per profile.">
<link rel="icon" type="image/png" href="/site/logo.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600&family=Poppins:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root { color-scheme: light; --wine:#540729; --wine-deep:#3A0419; --gold:#C9962E; --gold-light:#E8C25F;
          --ink:#1F1A1C; --muted:#6B6468; --rule:#EBE3DA; --ivory:#FAF7F2; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--ivory); color:var(--ink); line-height:1.6;
         font-family: Poppins, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  a { color: var(--wine); }
  header { background: linear-gradient(135deg, #6E0B37 0%, var(--wine) 55%, var(--wine-deep) 100%);
           color:#fff; border-bottom: 3px solid var(--gold); }
  .bar { max-width: 880px; margin: 0 auto; padding: 12px 16px; display:flex; align-items:center; gap:12px; flex-wrap:wrap; }
  .logo { display:flex; align-items:center; gap:10px; text-decoration:none; color:#fff; margin-right:auto; }
  .logo img { width:40px; height:40px; border-radius:10px; }
  .logo b { font-family:"Playfair Display", Georgia, serif; font-weight:600; font-size:1.25rem; color:var(--gold-light); line-height:1; }
  .logo small { display:block; font-size:.6rem; letter-spacing:.2em; text-transform:uppercase; opacity:.8; margin-top:3px; }
  nav { display:flex; gap:4px; flex-wrap:wrap; }
  nav a { color:#fff; text-decoration:none; font-size:.85rem; padding:6px 10px; border-radius:999px; opacity:.9; }
  nav a.on, nav a:hover { background: rgba(255,255,255,.14); opacity:1; }
  main { max-width: 880px; margin: 0 auto; padding: 20px 16px 32px; }
  h1, h2 { font-family:"Playfair Display", Georgia, serif; font-weight:600; color:var(--wine); line-height:1.2; }
  h1 { font-size:1.9rem; margin: 8px 0 6px; }
  h2 { font-size:1.25rem; margin: 26px 0 8px; }
  h3 { font-size:1rem; margin: 18px 0 4px; color: var(--wine-deep); }
  .lead { color: var(--muted); margin-top:0; }
  .card { background:#fff; border-radius:18px; padding: 18px 20px; margin-top:16px; box-shadow: 0 6px 22px rgba(58,4,25,.06); }
  .hero { text-align:center; padding: 28px 20px; }
  .hero img { width:96px; height:96px; border-radius:22px; box-shadow: 0 8px 24px rgba(84,7,41,.25); }
  .btns { display:flex; gap:10px; justify-content:center; flex-wrap:wrap; margin-top:16px; }
  .btn { display:inline-block; padding: 12px 20px; border-radius: 999px; text-decoration:none; font-weight:600; font-size:.95rem; }
  .btn.primary { background: var(--wine); color:#fff; }
  .btn.ghost { border: 1.5px solid var(--wine); color: var(--wine); }
  .note { font-size:.8rem; color: var(--muted); margin-top:10px; }
  .price { font-family:"Playfair Display", Georgia, serif; font-size:2.4rem; color: var(--wine); margin: 4px 0; }
  ol.steps { padding-left: 1.2rem; } ol.steps li { margin: 6px 0; }
  ul.plain { list-style:none; padding:0; margin: 6px 0; } ul.plain li { margin: 4px 0; }
  .grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }
  .grid .card { margin-top:0; }
  .updated { font-size:.8rem; color: var(--muted); }
  footer { border-top: 1px solid var(--rule); background:#fff; }
  footer .in { max-width: 880px; margin: 0 auto; padding: 18px 16px 26px; font-size:.82rem; color: var(--muted); }
  footer .links { display:flex; flex-wrap:wrap; gap: 6px 16px; margin-bottom: 10px; }
  footer a { color: var(--wine); text-decoration:none; }
</style>
</head><body>
<header><div class="bar">
  <a class="logo" href="/"><img src="/site/logo.png" alt=""><span><b>Wedbook</b><small>Matrimony</small></span></a>
  <nav>${nav}</nav>
</div></header>
<main>
${body}
</main>
<footer><div class="in">
  <div class="links">${foot}</div>
  <div>© 2026 ${esc(biz())}. Wedbook Matrimony and Wedbook Agent are Android apps.</div>
</div></footer>
</body></html>`;
}

const send = (route, title, body) => (_req, res) => res.type('html').send(layout(route, title, body()));

const downloadButtons = () => `
  <div class="btns">
    <a class="btn primary" href="/download/wedbook-matrimony.apk">Download Wedbook Matrimony</a>
    <a class="btn ghost" href="/download/wedbook-agent.apk">For bureau agents: Wedbook Agent</a>
  </div>
  <p class="note">Android apps. After the download, open the file; if Android asks, allow installing from this source.</p>`;

// ---- pages ---------------------------------------------------------------------

siteRouter.get('/', send('/', 'Home', () => `
<section class="card hero">
  <img src="/site/logo.png" alt="Wedbook Matrimony logo">
  <h1>Wedbook Matrimony</h1>
  <p class="lead">Find a life partner through trusted marriage bureau agents. Families register one profile,
  their agent checks and approves it, and contact details are shared only when both sides agree.</p>
  ${downloadButtons()}
</section>

<div class="grid" style="margin-top:16px">
  <section class="card">
    <h2 style="margin-top:0">How it works</h2>
    <ol class="steps">
      <li>Install Wedbook Matrimony, verify your mobile number with a one-time code (OTP) and choose a password.</li>
      <li>Look around as a guest: photos, age, job, community and package.</li>
      <li>Choose your marriage bureau agent and register your profile.</li>
      <li>Pay the one-time registration fee of ${rupees(fee())} in the app.</li>
      <li>Your agent approves your profile — it goes live, and you can open full profiles and send interests.</li>
    </ol>
  </section>
  <section class="card">
    <h2 style="margin-top:0">Price</h2>
    <div class="price">${rupees(fee())}</div>
    <p>One-time registration fee per profile. No subscription, no renewal. Pay by UPI, debit / credit card or
    net banking through Razorpay. Installing the app and browsing as a guest are free.</p>
    <p><a href="/pricing">Pricing details</a> · <a href="/refunds">Refund policy</a></p>
  </section>
  <section class="card">
    <h2 style="margin-top:0">Your privacy</h2>
    <p>Everyone sees only your main photo (watermarked), age and gender, plus the details you choose to show.
    Phone numbers, family and native-place details are shared only after your agent accepts an interest,
    and only for 15 days.</p>
    <p><a href="/privacy">Privacy policy</a></p>
  </section>
</div>`));

siteRouter.get('/about', send('/about', 'About us', () => `
<h1>About us</h1>
<section class="card">
  <p>Wedbook is a matrimony platform built for marriage bureaus and the families they serve. It is run by
  <b>${esc(biz())}</b>.</p>
  <p>It has two Android apps:</p>
  <ul>
    <li><b>Wedbook Matrimony</b> — for families. Sign in with your mobile number, register one profile with
    your agent's help, pay the ${rupees(fee())} registration fee, browse matching profiles and send interests.</li>
    <li><b>Wedbook Agent</b> — for marriage bureau agents. Agents are approved by our admins; they manage
    their families' profiles, approve new members, share masked profiles and handle contact requests.</li>
  </ul>
  <p>Every profile belongs to an agent who knows the family. Profiles are shown to the communities the family
  chooses, and personal contact details are released only with approval — so families can search with
  confidence and privacy.</p>
</section>`));

siteRouter.get('/contact', send('/contact', 'Contact us', () => `
<h1>Contact us</h1>
<section class="card">
  <p>Questions about your profile are best answered by your marriage bureau agent — their name and number are
  in the app. For payments, refunds, account deletion or anything else, contact us:</p>
  <ul class="plain">${contactItems()}</ul>
  <p>Please mention the mobile number you registered with. We usually reply within two working days.</p>
</section>`));

siteRouter.get('/pricing', send('/pricing', 'Pricing', () => `
<h1>Pricing</h1>
<p class="lead">All prices are in Indian Rupees (INR).</p>
<section class="card">
  <h2 style="margin-top:0">Profile registration fee</h2>
  <div class="price">${rupees(fee())} <span style="font-size:1rem">per profile, one-time</span></div>
  <ul>
    <li>Your profile is listed — once your agent approves it — to families and agents in the communities you choose.</li>
    <li>You can open full profiles, send interests, and see contact details when an interest is accepted.</li>
    <li>No subscription, no renewal, no hidden charges. One profile per account.</li>
    <li>Paid inside the Wedbook Matrimony app by UPI, debit / credit card or net banking (Razorpay).
    Your agent can also record a fee paid to them in cash.</li>
  </ul>
</section>
<section class="card">
  <h2 style="margin-top:0">Free</h2>
  <ul>
    <li>Installing Wedbook Matrimony, signing in, and browsing as a guest (photo, age, job, community, package).</li>
    <li>Wedbook Agent for marriage bureau agents approved by our admins.</li>
  </ul>
  <p>See the <a href="/refunds">Refund &amp; Cancellation policy</a> for when the fee is refunded.</p>
</section>`));

siteRouter.get('/terms', send('/terms', 'Terms & Conditions', () => `
<h1>Terms &amp; Conditions</h1>
<p class="updated">Last updated: ${UPDATED}</p>
<section class="card">
  <p>These terms apply to the Wedbook Matrimony and Wedbook Agent apps and this website, operated by
  <b>${esc(biz())}</b> ("we", "us"). You accept them when you sign up (the apps ask you to tick a box), and by using
  the apps.</p>
  <h3>1. The service</h3>
  <p>Wedbook lets families create matrimony profiles through marriage bureau agents, browse other profiles,
  and express interest. Agents are independent marriage bureaus approved by our admins.</p>
  <h3>2. Who may use it</h3>
  <p>Profiles may only be created for people of legal marriageable age under Indian law, by the person
  themselves or by a parent or guardian with their consent.</p>
  <h3>3. Your account</h3>
  <p>You sign in with your mobile number and your password; a one-time code verifies your number when you sign up
  or reset the password. One account can hold one profile. Keep your password and phone secure; you are
  responsible for activity on your account.</p>
  <h3>4. Profile content</h3>
  <p>Information and photos must be true, your own (or used with consent) and not misleading. Your agent
  reviews and approves profiles. We may hide or remove a profile, or suspend an account, that breaks these
  terms or the law.</p>
  <h3>5. Fees</h3>
  <p>A one-time registration fee of ${rupees(fee())} per profile applies (see <a href="/pricing">Pricing</a>).
  Refunds follow our <a href="/refunds">Refund &amp; Cancellation policy</a>.</p>
  <h3>6. Respectful use</h3>
  <p>Use other members' details only to consider a marriage proposal. Harassment, spam, collecting data,
  or sharing contact details outside the purpose of matchmaking is not allowed.</p>
  <h3>7. Objectionable content — not allowed</h3>
  <p>You must not post, upload or send anything that is:</p>
  <ul>
    <li>nudity, sexual or sexually suggestive content;</li>
    <li>hateful, discriminatory or abusive towards any person or group (including by caste, religion, gender or
    origin), or threatening, harassing or bullying;</li>
    <li>a fake profile, or impersonates someone, or uses another person's photos or details without their consent;</li>
    <li>about a person below the legal marriageable age;</li>
    <li>a scam, fraud, request for money, or advertising;</li>
    <li>violent, illegal, or encouraging illegal activity.</li>
  </ul>
  <p>We remove such content and may suspend or close the accounts involved, and report illegal content to the
  authorities.</p>
  <h3>8. Reporting and blocking</h3>
  <p>On any profile, tap <b>⋮ → Report profile</b> to tell us about a problem, or <b>⋮ → Block</b> to stop seeing it
  (in Wedbook Matrimony the other family also stops seeing yours). Blocked profiles can be unblocked from the app's
  settings. Our admins review reports promptly — we aim to act within 24 hours — and may hide the profile or suspend
  the account. You can also <a href="/contact">contact us</a>.</p>
  <h3>9. No guarantee</h3>
  <p>We do not guarantee a match or marriage, and we do not verify every statement in a profile. Please make
  your own enquiries before any commitment.</p>
  <h3>10. Liability</h3>
  <p>The service is provided "as is". To the extent the law allows, our liability for any claim is limited
  to the fee you paid us for the profile concerned.</p>
  <h3>11. Changes and law</h3>
  <p>We may update these terms; the date above shows the latest version. These terms are governed by the laws
  of India, and the courts at the place of our registered address have jurisdiction.</p>
  <h3>12. Contact</h3>
  <ul class="plain">${contactItems()}</ul>
</section>`));

// ---- privacy policies, one per app (SPEC §9.21) ------------------------------------

const POLICY_DATE = '13 November 2026';

const POLICY = {
  matrimony: {
    app: 'Wedbook Matrimony',
    pkg: 'com.matrimonyagents.gandharva',
    who: 'families looking for a life partner',
    deletion: '/delete-account/matrimony',
    collect: `
    <ul>
      <li><b>Account:</b> your mobile number, name and password (stored only as a one-way hash). Your number is verified
      with a one-time code (OTP) when you sign up or reset your password.</li>
      <li><b>Your matrimony profile</b> (entered by you or your marriage bureau agent): name, gender, date and time of
      birth, height, complexion, marital status, religion, community and sub-caste, gothram, star and raasi, education,
      profession and income, work country, native place, family details (parents, siblings, property), contact
      numbers, an "about" text and photos.</li>
      <li><b>Your choices:</b> which details others may see, which communities may see your profile, interests you send
      and receive.</li>
      <li><b>Payments:</b> the amount, date and status of your registration fee, and the UPI reference number (UTR) you
      type after paying. We never see your UPI PIN, card or bank details.</li>
      <li><b>Device:</b> a notification token if you allow notifications.</li>
      <li><b>Technical logs:</b> IP address and time of requests, kept for security.</li>
    </ul>`,
    seen: `
    <ul>
      <li><b>Everyone browsing</b> sees only your main photo (watermarked), age and gender, plus the details you choose
      to show in <i>Privacy settings</i>.</li>
      <li><b>Phone numbers, parents' and family details, native place, exact work place and property</b> are shown to
      another family only after your agent accepts their interest, and only for 15 days.</li>
      <li>Your profile is shown only to the communities you choose.</li>
      <li><b>Your agent</b> and our <b>admins</b> see your full profile to manage it. Other families never learn which
      agent manages your profile, and your profile ID is shown only to you, your agent and our admins.</li>
      <li>Profiles shared as links or PDFs never contain contact details.</li>
    </ul>`,
  },
  agent: {
    app: 'Wedbook Agent',
    pkg: 'com.matrimonyagents.matrimony_agents',
    who: 'marriage bureau agents',
    deletion: '/delete-account/agent',
    collect: `
    <ul>
      <li><b>Your agent account:</b> name, mobile number (verified by OTP), password (stored only as a one-way hash),
      agency name, city, State, your agent code and the communities you work with.</li>
      <li><b>Profiles you add for families:</b> the same matrimony details and photos the families give you (name, date
      and time of birth, community, education, work, income, family and contact details, photos). <b>You must have the
      family's consent</b> before adding their profile.</li>
      <li><b>Your activity:</b> contact requests, approvals, holds, shortlists, shares (every share is logged) and
      decisions on your clients.</li>
      <li><b>Payments:</b> amount, date and status of community fees, and the UPI reference number (UTR) you type. We
      never see your UPI PIN, card or bank details.</li>
      <li><b>Device:</b> a notification token if you allow notifications.</li>
      <li><b>Technical logs:</b> IP address and time of requests, kept for security.</li>
    </ul>`,
    seen: `
    <ul>
      <li><b>Other agents</b> see profiles shown to their communities — but phone numbers, parents' and family details,
      native place, exact work place and property only after the profile's own agent approves a contact request, and
      only for 15 days. Details a family has switched off stay hidden the same way.</li>
      <li><b>Families</b> using Wedbook Matrimony never see which agent manages a profile. When two agents handle an
      interest, they see each other's name, agency, phone and agent code so they can talk.</li>
      <li><b>Shared links, PDFs and photo cards</b> never contain contact details, the uploading agent or the profile ID.</li>
      <li>Our <b>admins</b> see everything in order to activate agents and resolve problems.</li>
    </ul>`,
  },
};

function privacyPolicy(key) {
  const p = POLICY[key];
  const name = esc(biz());
  return `
<h1>${p.app} — Privacy Policy</h1>
<p class="updated">Effective: ${POLICY_DATE}. App: ${p.app} (${p.pkg}) on Android.</p>
<section class="card">
  <h3>Who we are</h3>
  <p>${p.app} is a service for ${p.who}, run by <b>${name}</b> ("we", "us"). Under India's Digital Personal Data
  Protection Act, 2023, we are the <i>Data Fiduciary</i> for the personal data in the app. Contact details are at the
  end of this policy.</p>

  <h3>What we collect</h3>
  ${p.collect}

  <h3>Why we use it</h3>
  <ul>
    <li>To create and secure your account, and verify your mobile number with a one-time code.</li>
    <li>To show profiles to the right people, with the privacy choices that apply.</li>
    <li>To handle interests, contact requests and approvals, and to notify you about them.</li>
    <li>To confirm payments and keep the records the law requires.</li>
    <li>To keep the service safe: stop misuse, investigate complaints and fix problems.</li>
  </ul>
  <p>We use your data only with your consent, given when you sign up and when you add details. We do not sell personal
  data, and the app has no advertising or third-party analytics.</p>

  <h3>Who can see your data</h3>
  ${p.seen}

  <h3>Service providers we use</h3>
  <ul>
    <li><b>StartMessaging</b> (startmessaging.com) sends the one-time SMS codes — it receives your mobile number and the
    code.</li>
    <li><b>Oracle Cloud Infrastructure</b> hosts our servers, database and photos.</li>
    <li><b>Google Firebase Cloud Messaging</b> delivers app notifications when they are turned on — it receives a device
    token and the notification text.</li>
    <li><b>Your UPI app and bank</b> process UPI payments under their own terms; we only receive the reference number
    and amount. If you pay through Google Play, Google processes the payment under its own privacy policy.</li>
  </ul>
  <p>They may use the data only to provide their service to us. We share data with authorities only when Indian law
  requires it.</p>

  <h3>How long we keep it</h3>
  <ul>
    <li>Account and profile data: while your account exists.</li>
    <li>After you ask us to delete your account and we confirm it is you: deleted within <b>7 days</b>, and removed from
    our backups within a further <b>14 days</b>.</li>
    <li>One-time codes: stored only as a one-way hash and valid for 5 minutes. Contact approvals end after 15 days.</li>
    <li>Payment records (amount, date, reference): as long as Indian tax and accounting laws require.</li>
    <li>Technical logs: for a limited time, for security.</li>
  </ul>

  <h3>Deleting your account</h3>
  <p>In the app: <i>More → Delete my account</i>. On the web: <a href="${p.deletion}">${p.app} account deletion</a>.
  We call or WhatsApp your registered number to confirm, then delete your account and its data as described above.</p>

  <h3>Your rights</h3>
  <p>Under the DPDP Act, 2023 you can ask for a summary of your personal data and who it was shared with; correct or
  update it (in the app or through your agent); have it erased; withdraw your consent (by deleting your account); and
  nominate someone to exercise these rights if you cannot. Write to us using the contact details below. If you are
  not satisfied with our answer you can complain to the Data Protection Board of India.</p>

  <h3>Children</h3>
  <p>${p.app} is only for adults. Profiles may only be created for people of legal marriageable age under Indian law,
  by themselves or by a parent or guardian with their consent. We do not knowingly collect data from children.</p>

  <h3>Security</h3>
  <p>All traffic is encrypted (HTTPS). Passwords are stored only as one-way hashes, photos are served only to
  signed-in users (public copies are watermarked), new agents are activated by an admin, and every share and contact
  approval is logged.</p>

  <h3>Changes</h3>
  <p>We will update this page when our practices change and show the new effective date above; important changes are
  also announced in the app.</p>

  <h3>Contact and grievance officer</h3>
  <p>For privacy questions, corrections, deletion or complaints (Grievance Officer, ${name}):</p>
  <ul class="plain">${contactItems()}</ul>
  <p>We reply as soon as possible and within the time Indian law requires.</p>
</section>`;
}

siteRouter.get('/privacy', send('/privacy', 'Privacy Policy', () => `
<h1>Privacy Policy</h1>
<section class="card">
  <p>Wedbook has two Android apps. Each has its own privacy policy:</p>
  <ul>
    <li><a href="/privacy/matrimony"><b>Wedbook Matrimony</b> — for families</a></li>
    <li><a href="/privacy/agent"><b>Wedbook Agent</b> — for marriage bureau agents</a></li>
  </ul>
  <p>To delete an account: <a href="/delete-account/matrimony">Wedbook Matrimony</a> ·
  <a href="/delete-account/agent">Wedbook Agent</a>.</p>
</section>`));
siteRouter.get('/privacy/matrimony', send('/privacy', 'Wedbook Matrimony Privacy Policy', () => privacyPolicy('matrimony')));
siteRouter.get('/privacy/agent', send('/privacy', 'Wedbook Agent Privacy Policy', () => privacyPolicy('agent')));

siteRouter.get('/refunds', send('/refunds', 'Refund & Cancellation', () => `
<h1>Refund &amp; Cancellation Policy</h1>
<p class="updated">Last updated: ${UPDATED}</p>
<section class="card">
  <p>This policy covers the one-time profile registration fee of ${rupees(fee())}.</p>
  <h3>Before your profile is approved</h3>
  <p>You can cancel and get a <b>full refund</b> at any time until your agent approves your profile and it goes
  live. Ask your agent, or contact us with your registered mobile number.</p>
  <h3>After approval</h3>
  <p>Once your profile has been approved and is live, the service has been delivered and the fee is not refundable.</p>
  <h3>Double or failed payments</h3>
  <ul>
    <li>If you were charged twice for the same profile, the extra payment is always refunded in full.</li>
    <li>If money was deducted but the app shows the payment did not complete, it is either confirmed within a few
    minutes or returned automatically to your account by the bank / Razorpay.</li>
  </ul>
  <h3>How refunds are paid</h3>
  <p>Refunds go back to the original payment method (UPI, card or bank account) through Razorpay, usually within
  5–7 working days after we process them.</p>
  <h3>Cancelling a profile</h3>
  <p>An unpaid profile can be deleted in the app at any time. A paid profile is deleted with your agent's approval.</p>
  <h3>Contact</h3>
  <ul class="plain">${contactItems()}</ul>
</section>`));

siteRouter.get('/shipping', send('/shipping', 'Shipping & Delivery', () => `
<h1>Shipping &amp; Delivery Policy</h1>
<p class="updated">Last updated: ${UPDATED}</p>
<section class="card">
  <p>Wedbook is a digital service — nothing is shipped.</p>
  <ul>
    <li>Your payment is confirmed in the app straight away.</li>
    <li>Your profile goes live as soon as your marriage bureau agent approves it; you are notified in the app.</li>
    <li>From then on you can open full profiles and send interests from the app.</li>
  </ul>
  <p>Questions? <a href="/contact">Contact us</a>.</p>
</section>`));

// ---- assets and downloads ------------------------------------------------------------

siteRouter.get('/site/logo.png', (_req, res) => {
  res.set('Cache-Control', 'public, max-age=86400');
  res.sendFile(LOGO);
});

siteRouter.get('/download/:file', (req, res) => {
  const name = req.params.file;
  const label = DOWNLOADS[name];
  const file = label ? path.resolve(config.uploadsDir, 'downloads', name) : null;
  if (!file || !existsSync(file)) {
    return res
      .status(404)
      .type('html')
      .send(layout('', 'Download', `<h1>Download not available</h1><section class="card"><p>This app file is not
      available right now. Please ask your agent for the latest app, or <a href="/contact">contact us</a>.</p></section>`));
  }
  res.set('Cache-Control', 'no-cache');
  res.type('application/vnd.android.package-archive');
  res.download(file, name);
});

// ---- account deletion (SPEC §9.20 F, Google Play rule) ---------------------------

const APPS = { customer: 'Wedbook Matrimony', agent: 'Wedbook Agent' };

function deleteForm({ app = 'customer', phone = '', error = '', only = false } = {}) {
  const radio = (value) =>
    `<label style="display:block;margin:6px 0"><input type="radio" name="app" value="${value}"${
      app === value ? ' checked' : ''
    }> ${APPS[value]}</label>`;
  // An app's own page names the app and fixes the choice.
  const which = only
    ? `<input type="hidden" name="app" value="${app}"><p><b>App:</b> ${APPS[app]}</p>`
    : `<h3>Which app?</h3>${radio('customer')}${radio('agent')}`;
  return `
<h1>Delete your ${only ? `${APPS[app]} ` : ''}account</h1>
<section class="card">
  <p>Ask us to delete your <b>Wedbook Matrimony</b> or <b>Wedbook Agent</b> account and its data. We will call or
  WhatsApp the registered mobile number to confirm it is really you, then delete the account within <b>7 days</b>.</p>
  <h3>What is deleted</h3>
  <ul>
    <li>Your account, mobile number and name.</li>
    <li>Your matrimony profile, its photos and details, your interests and requests.</li>
    <li>For agents: your personal details and communities (profiles you manage for families are handed to another
    agent or deleted with the families' consent first).</li>
  </ul>
  <h3>What is kept</h3>
  <p>Payment records (amount, date, reference) are kept as long as tax and accounting law requires. Nothing else.
  Deleted data also leaves our backups within 14 days. Details: <a href="/privacy">Privacy Policy</a>.</p>
  ${error ? `<p style="color:#B3261E"><b>${esc(error)}</b></p>` : ''}
  <form method="post" action="/delete-account">
    ${which}
    <h3>Registered mobile number</h3>
    <input name="phone" value="${esc(phone)}" inputmode="numeric" maxlength="13" required
      style="width:100%;padding:12px;border:1px solid #D8CFC6;border-radius:12px;font-size:1rem">
    <h3>Your name (optional)</h3>
    <input name="full_name" maxlength="120"
      style="width:100%;padding:12px;border:1px solid #D8CFC6;border-radius:12px;font-size:1rem">
    <h3>Reason (optional)</h3>
    <textarea name="reason" maxlength="500" rows="3"
      style="width:100%;padding:12px;border:1px solid #D8CFC6;border-radius:12px;font-size:1rem"></textarea>
    <p><button class="btn primary" type="submit" style="border:0;cursor:pointer">Request deletion</button></p>
  </form>
  <p class="note">You can also delete an unpaid profile yourself in the app, or ask your agent.</p>
</section>`;
}

siteRouter.get('/delete-account', (req, res) => {
  const app = req.query.app === 'agent' ? 'agent' : 'customer';
  res.type('html').send(layout('/delete-account', 'Delete account', deleteForm({ app })));
});
// One page per app for the Play listings (SPEC §9.21).
siteRouter.get('/delete-account/matrimony', (_req, res) => {
  res.type('html').send(layout('/delete-account', 'Delete your Wedbook Matrimony account', deleteForm({ app: 'customer', only: true })));
});
siteRouter.get('/delete-account/agent', (_req, res) => {
  res.type('html').send(layout('/delete-account', 'Delete your Wedbook Agent account', deleteForm({ app: 'agent', only: true })));
});

// 10 requests per hour per address — the form is public.
const deleteLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (_req, res) =>
    res
      .status(429)
      .type('html')
      .send(layout('/delete-account', 'Delete account', '<h1>Too many requests</h1><section class="card"><p>Please try again in an hour, or <a href="/contact">contact us</a>.</p></section>')),
});

siteRouter.post('/delete-account', deleteLimiter, async (req, res, next) => {
  try {
    const app = req.body?.app === 'agent' ? 'agent' : 'customer';
    const parsed = phoneSchema.safeParse(String(req.body?.phone ?? ''));
    if (!parsed.success) {
      return res
        .status(400)
        .type('html')
        .send(layout('/delete-account', 'Delete account', deleteForm({ app, phone: req.body?.phone ?? '', error: 'Enter your 10-digit mobile number' })));
    }
    const clip = (v, n) => (String(v ?? '').trim().slice(0, n) || null);
    await createDeletionRequest({
      app,
      phone: parsed.data,
      fullName: clip(req.body?.full_name, 120),
      reason: clip(req.body?.reason, 500),
    });
    res.type('html').send(
      layout(
        '/delete-account',
        'Delete account',
        `<h1>Request received</h1><section class="card"><p>We have your request to delete the ${esc(APPS[app])} account
        for <b>+91 ${esc(parsed.data)}</b>. We will contact this number to confirm, then delete the account and its
        data within 7 days.</p><p><a href="/">Back to home</a></p></section>`,
      ),
    );
  } catch (e) {
    next(e);
  }
});
