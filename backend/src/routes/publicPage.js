import { Router } from 'express';
import { config } from '../lib/config.js';
import { many, one } from '../lib/db.js';
import { asyncHandler, notFound } from '../lib/errors.js';
import { escapeXml, watermarkedBuffer } from '../lib/photos.js';
import { ROW_GROUPS, formatDob, publicRows } from '../lib/card.js';

// Mounted at /p — PUBLIC, no auth. Masked view only (CLAUDE.md rule 6).
export const publicRouter = Router();

const esc = escapeXml;
const DEFAULT_LABEL = 'Mediator';

/** Loads the profile behind an active share token. */
async function loadShared(token) {
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(String(token || ''))) {
    throw notFound('link_not_found', 'This link is no longer available');
  }
  // Public columns only — nothing on request (SPEC §9.8) is even read here:
  // no native place, birth place/state/country, work place, NRI place,
  // parents, contact person, siblings, family details or property
  // (CLAUDE.md rule 6). Work country / NRI country are the location.
  const row = await one(
    `SELECT st.id AS token_id, st.token,
            p.id, p.full_name, p.gender, p.status,
            p.dob, date_part('year', age(p.dob))::int AS age, p.height_cm, p.weight_kg,
            to_char(p.birth_time, 'HH24:MI') AS birth_time,
            p.gothram, p.education_details, p.profession_details,
            p.income_text, p.other_income, p.is_nri, p.about,
            c.name AS community_name,
            sc.name AS subcaste_name,
            e.name AS education_name,
            pr.name AS profession_name,
            ot.name AS occupation_type_name,
            ms.name AS marital_status_name,
            cx.name AS complexion_name,
            co.name AS nri_country_name,
            wc.name AS work_country_name,
            na.name AS nationality_name,
            rl.name AS religion_name,
            mt.name AS mother_tongue_name,
            fh.name AS food_habit_name,
            z.english_name AS zodiac_english_name, z.indian_name AS zodiac_indian_name,
            n.name AS nakshatram_name,
            ag.agency_name,
            COALESCE((SELECT json_agg(json_build_object('id', l.id, 'name', l.name) ORDER BY l.sort_order, l.name)
                        FROM profile_languages pl JOIN languages l ON l.id = pl.language_id
                       WHERE pl.profile_id = p.id), '[]'::json) AS known_languages,
            COALESCE((SELECT json_agg(json_build_object(
                                 'level', el.level,
                                 'details', el.details,
                                 'country', CASE WHEN ec.id IS NULL THEN NULL
                                                 ELSE json_build_object('id', ec.id, 'name', ec.name) END)
                               ORDER BY array_position(ARRAY['below_10th','10th','intermediate','graduation','post_graduation'], el.level))
                        FROM profile_education_levels el LEFT JOIN countries ec ON ec.id = el.country_id
                       WHERE el.profile_id = p.id), '[]'::json) AS education_levels
       FROM share_tokens st
       JOIN profiles p ON p.id = st.profile_id
       JOIN communities c ON c.id = p.community_id
       JOIN agents ag ON ag.id = st.created_by
       LEFT JOIN subcastes sc ON sc.id = p.subcaste_id
       LEFT JOIN educations e ON e.id = p.education_id
       LEFT JOIN professions pr ON pr.id = p.profession_id
       LEFT JOIN occupation_types ot ON ot.id = p.occupation_type_id
       LEFT JOIN marital_statuses ms ON ms.id = p.marital_status_id
       LEFT JOIN complexions cx ON cx.id = p.complexion_id
       LEFT JOIN countries co ON co.id = p.nri_country_id
       LEFT JOIN countries wc ON wc.id = p.work_country_id
       LEFT JOIN countries na ON na.id = p.nationality_id
       LEFT JOIN religions rl ON rl.id = p.religion_id
       LEFT JOIN languages mt ON mt.id = p.mother_tongue_id
       LEFT JOIN food_habits fh ON fh.id = p.food_habit_id
       LEFT JOIN zodiac_signs z ON z.id = p.zodiac_id
       LEFT JOIN nakshatrams n ON n.id = p.nakshatram_id
      WHERE st.token = $1 AND st.active = TRUE`,
    [token],
  );
  // Once a profile stops being active — hidden, engaged or married — old links
  // must stop working, or stale profiles keep circulating on WhatsApp.
  if (!row || row.status !== 'active') throw notFound('link_not_found', 'This link is no longer available');
  return row;
}

// GET /p/:token — server-rendered masked page.
publicRouter.get(
  '/:token',
  asyncHandler(async (req, res) => {
    const p = await loadShared(req.params.token);
    const photos = await many(
      `SELECT id FROM profile_photos WHERE profile_id = $1 ORDER BY is_primary DESC, sort_order, id LIMIT 8`,
      [p.id],
    );

    // Same row list as the download card and the PDF (lib/card.js publicRows).
    const rows = publicRows({
      dob: p.dob,
      age: p.age,
      birth_time: p.birth_time,
      height_cm: p.height_cm,
      weight_kg: p.weight_kg,
      complexion: p.complexion_name ? { name: p.complexion_name } : null,
      religion: p.religion_name ? { name: p.religion_name } : null,
      community: { name: p.community_name },
      subcaste: p.subcaste_name ? { name: p.subcaste_name } : null,
      gothram: p.gothram,
      mother_tongue: p.mother_tongue_name ? { name: p.mother_tongue_name } : null,
      known_languages: Array.isArray(p.known_languages) ? p.known_languages : [],
      food_habit: p.food_habit_name ? { name: p.food_habit_name } : null,
      nationality: p.nationality_name ? { name: p.nationality_name } : null,
      marital_status: p.marital_status_name ? { name: p.marital_status_name } : null,
      education: p.education_name ? { name: p.education_name } : null,
      education_details: p.education_details,
      education_levels: Array.isArray(p.education_levels) ? p.education_levels : [],
      profession: p.profession_name ? { name: p.profession_name } : null,
      profession_details: p.profession_details,
      occupation_type: p.occupation_type_name ? { name: p.occupation_type_name } : null,
      work_country: p.work_country_name ? { name: p.work_country_name } : null,
      is_nri: p.is_nri,
      nri_country: p.nri_country_name ? { name: p.nri_country_name } : null,
      income_text: p.income_text,
      other_income: p.other_income,
      nakshatram: p.nakshatram_name ? { name: p.nakshatram_name } : null,
      zodiac: p.zodiac_english_name
        ? { english_name: p.zodiac_english_name, indian_name: p.zodiac_indian_name }
        : null,
    });
    const groups = ROW_GROUPS.map(([title, labels]) => [title, rows.filter(([k]) => labels.includes(k))]).filter(
      ([, r]) => r.length,
    );

    const label = p.agency_name || DEFAULT_LABEL;
    const who = p.gender === 'bride' ? 'Bride' : 'Groom';
    const sub = [who, p.age ? `${p.age} yrs${p.dob ? ` (${formatDob(p.dob)})` : ''}` : null, p.community_name]
      .filter(Boolean)
      .join('  ·  ');
    // Location in the preview = the country only (work country, or the NRI country).
    const location = p.is_nri ? p.nri_country_name : p.work_country_name;
    const description = [who, p.age ? `${p.age} yrs` : null, p.community_name, p.education_name, location]
      .filter(Boolean)
      .join(' · ');
    const pageUrl = `${config.publicBaseUrl}/p/${p.token}`;
    const ogImage = photos.length ? `${pageUrl}/photo/${photos[0].id}` : null;

    // Each photo is shown whole (SPEC §9.17): fitted inside the 4:5 frame over
    // a blurred copy of itself — same URL, so the browser fetches it once.
    const gallery = photos
      .map((ph, i) => {
        const src = `/p/${esc(p.token)}/photo/${ph.id}`;
        const loading = i ? 'lazy' : 'eager';
        return `<div class="shot"><img class="fill" src="${src}" alt="" aria-hidden="true" loading="${loading}"><img class="pic" src="${src}" alt="Photo ${i + 1}" loading="${loading}"></div>`;
      })
      .join('');
    const dots =
      photos.length > 1 ? `<div class="dots">${photos.map((_, i) => `<i${i ? '' : ' class="on"'}></i>`).join('')}</div>` : '';

    const section = (title, r) => `
    <section class="card">
      <h2>${esc(title)}</h2>
      <dl>${r.map(([k, v]) => `<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('')}</dl>
    </section>`;

    // Noindex: these links get forwarded around WhatsApp; keep them out of search.
    res.set('X-Robots-Tag', 'noindex, nofollow');
    res.type('html').send(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#0F2F52">
<title>${esc(p.full_name)} — Mediator</title>
<meta property="og:type" content="profile">
<meta property="og:site_name" content="Mediator · ${esc(label)}">
<meta property="og:title" content="${esc(p.full_name)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(pageUrl)}">
${ogImage ? `<meta property="og:image" content="${esc(ogImage)}">` : ''}
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600&family=Poppins:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root { color-scheme: light; --navy:#0F2F52; --navy-deep:#081C33; --gold:#C9962E; --gold-light:#E8C25F;
          --ink:#1C2430; --muted:#6B7280; --rule:#E7E2D8; --ivory:#F7F5F0; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--ivory); color:var(--ink);
         font-family: Poppins, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  .brand { background: linear-gradient(135deg, #1B4F82 0%, var(--navy) 55%, var(--navy-deep) 100%);
           color:#fff; padding: 14px 20px 16px; border-bottom: 3px solid var(--gold); }
  .brand .in { max-width: 600px; margin: 0 auto; display:flex; align-items:center; justify-content:space-between; gap:12px; }
  .brand .name { font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.35rem; color:var(--gold-light); line-height:1; }
  .brand .tag { font-size:.62rem; letter-spacing:.2em; text-transform:uppercase; opacity:.75; margin-top:4px; }
  .brand .agency { font-size:.8rem; font-weight:500; text-align:right; opacity:.92; }
  .wrap { max-width: 600px; margin: 0 auto; padding: 16px 16px 28px; }
  .hero { background:#fff; border-radius: 20px; overflow:hidden; box-shadow: 0 10px 30px rgba(8,28,51,.08); }
  .gallery { display:flex; overflow-x:auto; scroll-snap-type:x mandatory; background:var(--navy-deep); scrollbar-width:none; }
  .gallery::-webkit-scrollbar { display:none; }
  .shot { position:relative; overflow:hidden; width:100%; flex:0 0 100%; scroll-snap-align:center; aspect-ratio:4/5; }
  .shot img { position:absolute; inset:0; width:100%; height:100%; display:block; }
  .shot .fill { object-fit:cover; filter: blur(22px) brightness(.7); transform: scale(1.15); }
  .shot .pic { object-fit:contain; }
  .noimg { aspect-ratio:4/5; display:grid; place-items:center; color:var(--gold); font-size:1.1rem;
           background: radial-gradient(circle at 50% 40%, #1B4F82, var(--navy-deep)); }
  .dots { display:flex; justify-content:center; gap:6px; padding: 10px 0 0; }
  .dots i { width:7px; height:7px; border-radius:50%; background:#D6D0C4; display:block; }
  .dots i.on { background:var(--gold); }
  .head { padding: 18px 20px 20px; }
  h1 { margin:0; font-family: "Playfair Display", Georgia, serif; font-weight:600; font-size:1.7rem; color:var(--navy); line-height:1.15; }
  .sub { color:var(--gold); font-weight:600; font-size:.92rem; margin-top:6px; }
  .rule { width:48px; height:3px; background:var(--gold-light); border-radius:2px; margin-top:12px; }
  .card { background:#fff; border-radius: 18px; padding: 16px 20px 6px; margin-top: 14px;
          box-shadow: 0 6px 20px rgba(8,28,51,.05); }
  .card h2 { margin:0 0 6px; font-size:.7rem; letter-spacing:.16em; text-transform:uppercase; color:var(--gold); font-weight:600; }
  dl { margin:0; }
  dl > div { display:flex; gap:14px; padding: 10px 0; border-top: 1px solid var(--rule); }
  dl > div:first-child { border-top:0; }
  dt { flex: 0 0 38%; color:var(--muted); font-size:.86rem; }
  dd { margin:0; flex:1; font-weight:500; font-size:.93rem; }
  .about p { margin:0 0 12px; line-height:1.6; white-space:pre-wrap; font-size:.95rem; }
  .foot { text-align:center; padding: 26px 16px 10px; color:var(--muted); font-size:.85rem; }
  .foot .agency { font-weight:600; color:var(--navy); font-size:.95rem; }
  .foot .note { margin-top:4px; }
  .foot .by { margin-top:14px; font-size:.72rem; letter-spacing:.08em; text-transform:uppercase; opacity:.7; }
</style>
</head><body>
<header class="brand"><div class="in">
  <div><div class="name">Mediator</div><div class="tag">Matrimony Partners</div></div>
  <div class="agency">${esc(label)}</div>
</div></header>
<main class="wrap">
  <div class="hero">
    <div class="gallery">${gallery || '<div class="noimg">No photo</div>'}</div>
    ${dots}
    <div class="head">
      <h1>${esc(p.full_name)}</h1>
      <div class="sub">${esc(sub)}</div>
      <div class="rule"></div>
    </div>
  </div>
  ${groups.map(([title, r]) => section(title, r)).join('')}
  ${p.about ? `<section class="card about"><h2>About</h2><p>${esc(p.about)}</p></section>` : ''}
  <footer class="foot">
    <div class="agency">${esc(label)}</div>
    <div class="note">Contact your agent for details</div>
    <div class="by">Shared privately via Mediator</div>
  </footer>
</main>
</body></html>`);
  }),
);

// GET /p/:token/photo/:photoId — watermarked copy only.
publicRouter.get(
  '/:token/photo/:photoId',
  asyncHandler(async (req, res) => {
    const p = await loadShared(req.params.token);
    const photo = await one('SELECT id, file_path FROM profile_photos WHERE id = $1 AND profile_id = $2', [
      Number(req.params.photoId),
      p.id,
    ]);
    if (!photo) throw notFound('photo_not_found', 'Photo not found');

    const buf = await watermarkedBuffer(photo.file_path, p.agency_name || DEFAULT_LABEL);
    res.set({
      'Content-Type': 'image/jpeg',
      'Content-Length': buf.length,
      'Cache-Control': 'public, max-age=3600',
      'X-Robots-Tag': 'noindex, nofollow',
    });
    res.send(buf);
  }),
);
