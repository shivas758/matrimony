// Privacy toggles — SPEC §9.18 D. A family switches individual details of
// their profile off; a switched-off detail behaves like the on-request block
// (SPEC §9.8): it is shown to the uploader, admins, an agent with a live
// approved contact request, the owning customer and a customer whose interest
// is accepted and unexpired — and to nobody else, in no list, share, PDF,
// public page or notification.
//
// The main photo, age and gender are always shown and have no toggle.
//
// ONE list (PRIVACY_FIELDS) drives everything: what GET /masters offers the
// apps, what a profile body may store, what mask() removes and which filters
// are guarded (lib/profileQuery.js).

/** key → what the family sees on the toggle. `section` groups them like the form's steps. */
export const PRIVACY_FIELDS = [
  { key: 'name', label: 'Name', section: 'personal', hint: 'Others see a profile number instead' },
  { key: 'dob', label: 'Date of birth', section: 'personal', hint: 'Age is always shown' },
  { key: 'marital_status', label: 'Marital status', section: 'personal', hint: null },
  { key: 'religion', label: 'Religion', section: 'personal', hint: null },
  { key: 'community', label: 'Community / caste', section: 'personal', hint: 'Also hides the subcaste' },
  { key: 'subcaste', label: 'Subcaste', section: 'personal', hint: null },
  { key: 'mother_tongue', label: 'Mother tongue', section: 'personal', hint: null },
  { key: 'known_languages', label: 'Languages known', section: 'personal', hint: null },
  { key: 'height', label: 'Height', section: 'personal', hint: null },
  { key: 'weight', label: 'Weight', section: 'personal', hint: null },
  { key: 'complexion', label: 'Complexion', section: 'personal', hint: null },
  { key: 'food_habit', label: 'Food habit', section: 'personal', hint: null },
  { key: 'nationality', label: 'Nationality', section: 'personal', hint: null },
  { key: 'about', label: 'About', section: 'personal', hint: null },
  { key: 'photos', label: 'Other photos', section: 'personal', hint: 'The main photo is always shown' },
  { key: 'education', label: 'Education', section: 'professional', hint: null },
  { key: 'profession', label: 'Profession / occupation', section: 'professional', hint: null },
  { key: 'income', label: 'Income / package', section: 'professional', hint: null },
  { key: 'work_location', label: 'Work country / NRI', section: 'professional', hint: null },
  { key: 'star_rasi', label: 'Star & Rasi', section: 'horoscope', hint: null },
  { key: 'gothram', label: 'Gothram', section: 'horoscope', hint: null },
  { key: 'birth_time', label: 'Birth time', section: 'horoscope', hint: null },
];

export const PRIVACY_KEYS = PRIVACY_FIELDS.map((f) => f.key);
export const PRIVACY_ALWAYS_VISIBLE = ['Main photo', 'Age', 'Gender'];

const KNOWN = new Set(PRIVACY_KEYS);

/**
 * The details a profile row hides, as a Set — what the family stored plus
 * what follows from it (a hidden community hides the subcaste: a subcaste
 * belongs to exactly one community). `hiddenFields` is profiles.hidden_fields
 * (a JS array from pg, or from json_agg).
 */
export function hiddenSet(hiddenFields) {
  const set = new Set((Array.isArray(hiddenFields) ? hiddenFields : []).filter((k) => KNOWN.has(k)));
  if (set.has('community')) set.add('subcaste');
  return set;
}

export const hidesName = (hiddenFields) => hiddenSet(hiddenFields).has('name');

/**
 * What a viewer without access reads instead of a hidden name. The numeric
 * profile id — never the profile ID of SPEC §9.18 C, which carries the
 * agent's code (uploader identity, CLAUDE.md rule 3).
 */
export const neutralName = (profileId) => `Profile ${profileId}`;

/** The name to show: the real one with access (or when it is not hidden), else the neutral label. */
export function displayName({ id, full_name, hidden_fields }, reveal = false) {
  return reveal || !hidesName(hidden_fields) ? full_name : neutralName(id);
}

/**
 * Removes the hidden details from a profilePublic() object IN PLACE for a
 * viewer without access and returns the keys that were withheld (in
 * PRIVACY_FIELDS order). Values become null ([] for lists, false for is_nri);
 * the name becomes the neutral label; only the main photo stays.
 */
export function mask(out, hiddenFields) {
  const hidden = hiddenSet(hiddenFields);
  if (!hidden.size) return [];
  if (hidden.has('name')) out.full_name = neutralName(out.id);
  if (hidden.has('dob')) out.dob = null;
  if (hidden.has('marital_status')) out.marital_status = null;
  if (hidden.has('religion')) out.religion = null;
  if (hidden.has('community')) out.community = null;
  if (hidden.has('subcaste')) out.subcaste = null;
  if (hidden.has('mother_tongue')) out.mother_tongue = null;
  if (hidden.has('known_languages')) out.known_languages = [];
  if (hidden.has('height')) out.height_cm = null;
  if (hidden.has('weight')) out.weight_kg = null;
  if (hidden.has('complexion')) out.complexion = null;
  if (hidden.has('food_habit')) out.food_habit = null;
  if (hidden.has('nationality')) out.nationality = null;
  if (hidden.has('about')) out.about = null;
  if (hidden.has('photos') && Array.isArray(out.photos)) out.photos = out.photos.slice(0, 1);
  if (hidden.has('education')) {
    out.education = null;
    out.education_details = null;
    out.education_levels = [];
  }
  if (hidden.has('profession')) {
    out.profession = null;
    out.profession_details = null;
    out.occupation_type = null;
  }
  if (hidden.has('income')) {
    out.income_text = null;
    out.other_income = null;
  }
  if (hidden.has('work_location')) {
    out.work_country = null;
    out.is_nri = false;
    out.nri_country = null;
  }
  if (hidden.has('star_rasi')) {
    out.zodiac = null;
    out.nakshatram = null;
  }
  if (hidden.has('gothram')) out.gothram = null;
  if (hidden.has('birth_time')) out.birth_time = null;
  return PRIVACY_KEYS.filter((k) => hidden.has(k));
}

/**
 * Who the list filters run for (lib/profileQuery.js): admins see through
 * every toggle, an agent through the toggles of their own uploads, a customer
 * through none (their own profile is never in a browse list).
 */
export const filterViewer = ({ agent = null } = {}) => ({
  seeAll: Boolean(agent?.is_admin),
  ownerAgentId: agent && !agent.is_admin ? Number(agent.id) : null,
});

/**
 * SQL (profiles aliased `p`) that is TRUE when the viewer may be matched on
 * the detail `key` of that profile: it is not hidden, or the profile is the
 * viewer's own upload. '' for admins. Guards every filter on a hideable
 * detail so that filtering can never reveal a hidden value.
 */
export function visibleSql(key, viewer) {
  if (viewer.seeAll) return 'TRUE';
  // Hiding the community hides the subcaste too (hiddenSet()).
  const keys = key === 'subcaste' ? `ARRAY['subcaste','community']` : `ARRAY['${key}']`;
  const own = viewer.ownerAgentId ? ` OR p.uploaded_by = ${Number(viewer.ownerAgentId)}` : '';
  return `(NOT (p.hidden_fields && ${keys}::text[])${own})`;
}
