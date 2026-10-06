import sharp from 'sharp';
import { escapeXml, resolveStoredPath } from './photos.js';

// WhatsApp-friendly portrait card.
const W = 1080;
const H = 1560;
const PHOTO_H = 620;
const PAD = 56;
const FOOTER_H = 130;
const ROW_STEP = 36;

const FONT = 'DejaVu Sans, Noto Sans, Arial, sans-serif';

// Brand palette — mirrors app/lib/ui/theme.dart and lib/pdf.js.
const NAVY = '#0F2F52';
const NAVY_DEEP = '#081C33';
const GOLD = '#C9962E';
const GOLD_LIGHT = '#E8C25F';
const INK = '#1C2430';
const MUTED = '#6B7280';
const IVORY = '#F7F5F0';

/** Greedy word wrap by estimated character width. */
function wrap(text, maxChars) {
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const w of words) {
    const next = line ? `${line} ${w}` : w;
    if (next.length > maxChars && line) {
      lines.push(line);
      line = w;
    } else {
      line = next;
    }
  }
  if (line) lines.push(line);
  return lines;
}

/**
 * How the public rows are grouped on the PDF and the public page. Labels must
 * match publicRows() exactly.
 */
export const ROW_GROUPS = [
  [
    'Personal',
    [
      'Age', 'Height', 'Weight', 'Complexion', 'Marital status', 'Religion', 'Community', 'Subcaste',
      'Gothram', 'Mother tongue', 'Languages known', 'Food habit', 'Nationality',
    ],
  ],
  [
    'Education & Career',
    ['Education', 'Qualifications', 'Profession', 'Occupation type', 'Works in', 'NRI', 'Income', 'Other income'],
  ],
  ['Horoscope', ['Star / Rasi', 'Birth time']],
];

/** Display labels for profile_education_levels.level (SPEC §9.7). */
export const EDUCATION_LEVEL_LABELS = {
  below_10th: 'Below 10th',
  '10th': '10th',
  intermediate: 'Intermediate / 12th',
  graduation: 'Graduation',
  post_graduation: 'Post graduation',
};

/**
 * The public rows of a profile, in display order. Shared by the download card,
 * the PDF and the public page so the three can never drift apart on what is
 * exposed. NEVER add an on-request field here (SPEC §3.3 / §9.8,
 * CLAUDE.md rule 3): native place (city/state), birth place/state/country,
 * work place, NRI place, parents' names/occupations/phones, contact person,
 * siblings (has/count/details/breakdown), family details, property share /
 * details — nor uploader identity. Work country / NRI country are the only
 * location that leaves the app.
 */
export function publicRows(profile, { maxDetail = Infinity } = {}) {
  const trim = (s) => (s && s.length > maxDetail ? `${s.slice(0, maxDetail - 1)}…` : s);
  return [
    // Age with the date of birth in brackets — families check the DOB for horoscopes.
    ['Age', profile.age ? `${profile.age} years${profile.dob ? ` (${formatDob(profile.dob)})` : ''}` : null],
    ['Height', profile.height_cm ? formatHeight(profile.height_cm) : null],
    ['Weight', profile.weight_kg ? `${profile.weight_kg} kg` : null],
    ['Complexion', profile.complexion?.name],
    ['Marital status', profile.marital_status?.name],
    ['Religion', profile.religion?.name],
    ['Community', profile.community?.name],
    ['Subcaste', profile.subcaste?.name],
    ['Gothram', profile.gothram],
    ['Mother tongue', profile.mother_tongue?.name],
    ['Languages known', languagesLabel(profile)],
    ['Food habit', profile.food_habit?.name],
    ['Nationality', profile.nationality?.name],
    ['Education', withDetails(profile.education?.name, trim(profile.education_details))],
    ['Qualifications', qualificationsLabel(profile, trim)],
    ['Profession', withDetails(profile.profession?.name, trim(profile.profession_details))],
    ['Occupation type', profile.occupation_type?.name],
    // Public coarse location. For NRI profiles the 'NRI' row carries the country.
    ['Works in', !profile.is_nri ? profile.work_country?.name : null],
    ['NRI', nriLabel(profile)],
    ['Income', profile.income_text],
    ['Other income', profile.other_income],
    ['Star / Rasi', starRasi(profile)],
    ['Birth time', formatBirthTime(profile.birth_time)],
  ].filter(([, v]) => v);
}

/**
 * A masked profile card: photo + public fields only (publicRows). NEVER add an
 * on-request field or uploader identity here (CLAUDE.md rule 3, SPEC §9.8).
 */
export async function renderProfileCard(profile, { agencyLabel } = {}) {
  const label = agencyLabel || 'Mediator';

  // One line per row on the card, so long descriptions get cut short.
  const rows = publicRows(profile, { maxDetail: 34 });

  const title = escapeXml(profile.full_name);
  const subtitle = escapeXml(
    [
      profile.gender === 'bride' ? 'Bride' : 'Groom',
      profile.age ? `${profile.age} yrs` : null,
      profile.community?.name,
    ]
      .filter(Boolean)
      .join('  ·  '),
  );

  // The text layer must stay transparent above PHOTO_H, otherwise it paints
  // over the photo composited underneath it.
  const textBottom = H - FOOTER_H - 16;
  let y = PHOTO_H + 84;
  const parts = [
    `<text x="${PAD}" y="${y}" font-family="${FONT}" font-size="50" font-weight="bold" fill="${NAVY}">${title}</text>`,
  ];
  y += 44;
  parts.push(
    `<text x="${PAD}" y="${y}" font-family="${FONT}" font-size="28" font-weight="bold" fill="${GOLD}">${subtitle}</text>`,
  );
  y += 22;
  parts.push(`<rect x="${PAD}" y="${y}" width="72" height="4" rx="2" fill="${GOLD_LIGHT}"/>`);
  y += 44;

  for (const [k, v] of rows) {
    if (y > textBottom) break;
    parts.push(
      `<text x="${PAD}" y="${y}" font-family="${FONT}" font-size="26" fill="${MUTED}">${escapeXml(k)}</text>`,
      `<text x="${PAD + 300}" y="${y}" font-family="${FONT}" font-size="27" fill="${INK}">${escapeXml(v)}</text>`,
    );
    y += ROW_STEP;
  }

  if (profile.about) {
    y += 12;
    for (const line of wrap(profile.about, 62).slice(0, 3)) {
      if (y > textBottom) break;
      parts.push(
        `<text x="${PAD}" y="${y}" font-family="${FONT}" font-size="25" fill="#444444">${escapeXml(line)}</text>`,
      );
      y += 32;
    }
  }

  const svg = Buffer.from(
    `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
       <rect x="0" y="${PHOTO_H}" width="${W}" height="${H - PHOTO_H}" fill="#ffffff"/>
       <rect x="0" y="${PHOTO_H}" width="${W}" height="8" fill="${GOLD}"/>
       ${parts.join('\n')}
       <rect x="0" y="${H - FOOTER_H}" width="${W}" height="${FOOTER_H}" fill="${NAVY}"/>
       <rect x="0" y="${H - FOOTER_H}" width="${W}" height="4" fill="${GOLD}"/>
       <text x="${PAD}" y="${H - 74}" font-family="${FONT}" font-size="30" font-weight="bold"
             fill="${GOLD_LIGHT}">${escapeXml(label)}</text>
       <text x="${PAD}" y="${H - 36}" font-family="${FONT}" font-size="24"
             fill="#ffffff" fill-opacity="0.8">Contact your agent for details</text>
       <text x="${W - PAD}" y="${H - 52}" font-family="${FONT}" font-size="26" font-weight="bold"
             fill="#ffffff" fill-opacity="0.55" text-anchor="end">Mediator</text>
     </svg>`,
  );

  const layers = [{ input: svg, top: 0, left: 0 }];

  const photoPath = profile.__photoPath ? resolveStoredPath(profile.__photoPath) : null;
  if (photoPath) {
    try {
      const photo = await sharp(photoPath)
        .rotate()
        .resize({ width: W, height: PHOTO_H, fit: 'cover', position: 'attention' })
        .toBuffer();
      layers.unshift({ input: photo, top: 0, left: 0 });
    } catch {
      // Missing/unreadable file: fall through to the placeholder band below.
    }
  }
  if (layers.length === 1) {
    const placeholder = Buffer.from(
      `<svg width="${W}" height="${PHOTO_H}" xmlns="http://www.w3.org/2000/svg">
         <rect width="${W}" height="${PHOTO_H}" fill="${NAVY_DEEP}"/>
         <text x="${W / 2}" y="${PHOTO_H / 2}" font-family="${FONT}" font-size="40" fill="${GOLD}"
               text-anchor="middle" dominant-baseline="central">No photo</text>
       </svg>`,
    );
    layers.unshift({ input: await sharp(placeholder).png().toBuffer(), top: 0, left: 0 });
  }

  return sharp({ create: { width: W, height: H, channels: 3, background: IVORY } })
    .composite(layers)
    .jpeg({ quality: 88 })
    .toBuffer();
}

/** Feet-inches first — that is how families talk about height — cm alongside. */
export function formatHeight(cm) {
  const totalInches = Math.round(cm / 2.54);
  return `${Math.floor(totalInches / 12)}' ${totalInches % 12}" (${cm} cm)`;
}

/** "B.Tech / B.E. — CSE, JNTU 2018"; either half alone when the other is empty. */
export function withDetails(name, details) {
  return [name, details].filter(Boolean).join(' — ') || null;
}

/**
 * "United States" for NRI profiles, null otherwise. The exact NRI place is on
 * request (SPEC §9.8), so only the country ever leaves the app.
 */
export function nriLabel(profile) {
  if (!profile.is_nri) return null;
  return profile.nri_country?.name || 'Yes';
}

/**
 * "10th: SSC Board · Graduation: B.Tech CSE (United States)" from
 * education_levels; the country is shown only when it is not India.
 * `trim` shortens each details text for the one-line card.
 */
export function qualificationsLabel(profile, trim = (s) => s) {
  const levels = Array.isArray(profile.education_levels) ? profile.education_levels : [];
  const parts = levels
    .map((lv) => {
      const label = EDUCATION_LEVEL_LABELS[lv?.level];
      if (!label) return null;
      const details = trim(lv.details || '');
      const country = lv.country?.name;
      const abroad = country && country.toLowerCase() !== 'india' ? ` (${country})` : '';
      return `${label}${details ? `: ${details}` : ''}${abroad}`;
    })
    .filter(Boolean);
  return parts.length ? parts.join(' · ') : null;
}

export function starRasi(profile) {
  const star = profile.nakshatram?.name;
  const rasi = profile.zodiac ? `${profile.zodiac.indian_name} / ${profile.zodiac.english_name}` : null;
  return [star, rasi].filter(Boolean).join(' · ') || null;
}

/** "Telugu, Hindi, English" or null. */
export function languagesLabel(profile) {
  const names = (profile.known_languages ?? []).map((l) => l?.name).filter(Boolean);
  return names.length ? names.join(', ') : null;
}

/** 1998-04-12 (Date or ISO string) → "12 Apr 1998"; null when unparseable. */
export function formatDob(dob) {
  if (!dob) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  // node-postgres hands DATE columns over as a Date at LOCAL midnight, so read
  // it with local getters; a bare "YYYY-MM-DD" string is read as written.
  if (dob instanceof Date) {
    if (Number.isNaN(dob.getTime())) return null;
    return `${dob.getDate()} ${months[dob.getMonth()]} ${dob.getFullYear()}`;
  }
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dob));
  if (!m) return null;
  return `${Number(m[3])} ${months[Number(m[2]) - 1]} ${m[1]}`;
}

/** "22:40" → "10:40 PM" — how bio-data print the time of birth. */
export function formatBirthTime(t) {
  const m = /^(\d{2}):(\d{2})/.exec(String(t ?? ''));
  if (!m) return null;
  const h = Number(m[1]);
  const suffix = h < 12 ? 'AM' : 'PM';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${m[2]} ${suffix}`;
}
