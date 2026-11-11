// Public website at the domain root — SPEC §9.19 E. The pages a payment gateway
// (Razorpay) reviews: home with the app downloads, about, contact, pricing,
// terms, privacy, refunds, shipping. No login, no tracking, no data from the
// database — only the fee and the business identity from config.
import { Router } from 'express';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../lib/config.js';
import { escapeXml as esc } from '../lib/photos.js';

export const siteRouter = Router();

const LOGO = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'site', 'logo.png');
const DOWNLOADS = {
  'wedbook-matrimony.apk': 'Wedbook Matrimony',
  'wedbook-agent.apk': 'Wedbook Agent',
};
const UPDATED = '11 November 2026';

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
      <li>Install Wedbook Matrimony and sign in with your mobile number and a one-time code (OTP).</li>
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
  <b>${esc(biz())}</b> ("we", "us"). By using them you agree to these terms.</p>
  <h3>1. The service</h3>
  <p>Wedbook lets families create matrimony profiles through marriage bureau agents, browse other profiles,
  and express interest. Agents are independent marriage bureaus approved by our admins.</p>
  <h3>2. Who may use it</h3>
  <p>Profiles may only be created for people of legal marriageable age under Indian law, by the person
  themselves or by a parent or guardian with their consent.</p>
  <h3>3. Your account</h3>
  <p>You sign in with your mobile number and a one-time code. One account can hold one profile. Keep your
  phone secure; you are responsible for activity on your account.</p>
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
  <h3>7. No guarantee</h3>
  <p>We do not guarantee a match or marriage, and we do not verify every statement in a profile. Please make
  your own enquiries before any commitment.</p>
  <h3>8. Liability</h3>
  <p>The service is provided "as is". To the extent the law allows, our liability for any claim is limited
  to the fee you paid us for the profile concerned.</p>
  <h3>9. Changes and law</h3>
  <p>We may update these terms; the date above shows the latest version. These terms are governed by the laws
  of India, and the courts at the place of our registered address have jurisdiction.</p>
  <h3>10. Contact</h3>
  <ul class="plain">${contactItems()}</ul>
</section>`));

siteRouter.get('/privacy', send('/privacy', 'Privacy Policy', () => `
<h1>Privacy Policy</h1>
<p class="updated">Last updated: ${UPDATED}</p>
<section class="card">
  <p>This policy explains what <b>${esc(biz())}</b> collects in the Wedbook apps and how it is used.</p>
  <h3>What we collect</h3>
  <ul>
    <li>Your mobile number (to sign you in with a one-time code).</li>
    <li>Profile details you or your agent enter: name, date of birth, community, education, work, income,
    horoscope, family details, contact numbers and photos.</li>
    <li>Payment status of your registration fee. Card, UPI and bank details are handled by Razorpay — we never
    see or store them.</li>
    <li>If you allow notifications, a device token to send them.</li>
  </ul>
  <h3>Who sees your profile</h3>
  <ul>
    <li>Always shown: your main photo (watermarked), age and gender.</li>
    <li>Other details: shown according to the privacy switches you choose in the app.</li>
    <li>Contact numbers, parents' and family details, native place, exact work place and property are shared
    only when your agent accepts another member's interest or an agent's contact request — and only for 15 days.</li>
    <li>Profiles are shown only to the communities you choose. Who uploaded a profile is never shown to other families.</li>
    <li>Shared links and downloads never contain contact details.</li>
  </ul>
  <h3>Service providers</h3>
  <p>We use an SMS provider to deliver one-time codes, Razorpay for payments, a cloud hosting provider to run
  the service, and Google Firebase to deliver app notifications. They receive only what they need for that job.
  We do not sell your data.</p>
  <h3>Keeping and deleting data</h3>
  <p>We keep your data while your account is in use. You can delete an unpaid profile in the app; a paid profile
  is deleted with your agent's approval. To delete your account, contact your agent or us (below).</p>
  <h3>Security</h3>
  <p>All traffic is encrypted (HTTPS), photos are served only to signed-in users (public copies are watermarked),
  and passwords are stored hashed.</p>
  <h3>Contact</h3>
  <ul class="plain">${contactItems()}</ul>
</section>`));

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
