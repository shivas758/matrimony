// Profile list filters shared by the agent list (GET /profiles, SPEC §4) and
// the customer list (GET /customer/profiles, SPEC §9.9). Only the search
// filters live here — visibility, `mine` and `status` stay in the routes,
// because who may see what differs between agents and customers.
//
// Privacy toggles (SPEC §9.18 D): a filter on a detail the family switched
// off must not match that profile for other viewers — otherwise filtering by
// "Community = X" would reveal a hidden community. Every clause on a hideable
// detail is therefore paired with visibleSql(key, viewer) (lib/privacy.js):
// the viewer's own uploads still match, admins match everything.

import { z } from 'zod';
import { badRequest } from './errors.js';
import { idListQuery, intQuery } from './validate.js';
import { visibleSql } from './privacy.js';

export const listQuerySchema = z.object({
  gender: z.enum(['bride', 'groom']).optional(),
  age_min: intQuery(18, 100),
  age_max: intQuery(18, 100),
  height_min: intQuery(100, 250),
  height_max: intQuery(100, 250),
  community_id: idListQuery,
  subcaste_id: idListQuery,
  education_id: idListQuery,
  profession_id: idListQuery,
  occupation_type_id: idListQuery,
  marital_status_id: idListQuery,
  complexion_id: idListQuery,
  religion_id: idListQuery,
  mother_tongue_id: idListQuery,
  // Known languages: any of.
  language_id: idListQuery,
  food_habit_id: idListQuery,
  zodiac_id: idListQuery,
  nakshatram_id: idListQuery,
  // NRI: nri=true narrows to NRI profiles; country_id narrows further (any of).
  nri: z.enum(['true', 'false']).optional(),
  country_id: idListQuery,
  // Public coarse location (SPEC §9.8): country of work, any of.
  work_country_id: idListQuery,
  city: z.string().trim().max(80).optional(),
  // Name — and, on the caller's own uploads, the profile ID (SPEC §9.18 C).
  q: z.string().trim().max(80).optional(),
  status: z.enum(['active', 'engaged', 'married', 'hidden', 'on_hold']).optional(),
  mine: z.enum(['true', 'false']).optional(),
  sort: z.enum(['newest', 'oldest', 'name', 'age_asc', 'age_desc']).default('newest'),
  page: intQuery(1).default(1),
  limit: intQuery(1, 100).default(20),
});

const SORTS = {
  newest: 'p.created_at DESC, p.id DESC',
  oldest: 'p.created_at ASC, p.id ASC',
  age_asc: 'p.dob DESC, p.id ASC',
  age_desc: 'p.dob ASC, p.id ASC',
};

/**
 * ORDER BY for a list. Sorting by name never orders on a name the viewer may
 * not read: hidden names go last (SPEC §9.18 D). `viewer` is filterViewer().
 */
export function sortSql(sort, viewer) {
  if (sort !== 'name') return SORTS[sort] ?? SORTS.newest;
  if (viewer.seeAll) return 'p.full_name ASC, p.id ASC';
  return `CASE WHEN ${visibleSql('name', viewer)} THEN p.full_name END ASC NULLS LAST, p.id ASC`;
}

/**
 * Adds the search filters of a parsed listQuerySchema `f` through `add(sql,
 * ...vals)`, where every `$#` in `sql` becomes the next placeholder (see the
 * routes for the helper). The profiles table must be aliased `p`.
 * `viewer` is filterViewer() — who is searching, for the privacy guards.
 * Not here: visibility, mine, status.
 */
export function applyListFilters(f, add, viewer) {
  if (f.age_min !== undefined && f.age_max !== undefined && f.age_min > f.age_max) {
    throw badRequest('bad_age_range', 'Minimum age cannot exceed maximum age');
  }
  /** `sql` AND "the viewer may be matched on `key` of this profile". */
  const guarded = (key, sql, ...vals) => add(`(${sql} AND ${visibleSql(key, viewer)})`, ...vals);

  // Gender and age are always shown (SPEC §9.18 D) — no guard.
  if (f.gender) add('p.gender = $#', f.gender);
  // Age -> dob range so the (gender, dob) index stays usable.
  if (f.age_min !== undefined) add('p.dob <= (current_date - make_interval(years => $#))', f.age_min);
  if (f.age_max !== undefined) add('p.dob > (current_date - make_interval(years => $#))', f.age_max + 1);
  if (f.height_min !== undefined) guarded('height', 'p.height_cm >= $#', f.height_min);
  if (f.height_max !== undefined) guarded('height', 'p.height_cm <= $#', f.height_max);
  if (f.community_id) guarded('community', 'p.community_id = ANY($#::int[])', f.community_id);
  if (f.subcaste_id) guarded('subcaste', 'p.subcaste_id = ANY($#::int[])', f.subcaste_id);
  if (f.education_id) guarded('education', 'p.education_id = ANY($#::int[])', f.education_id);
  if (f.profession_id) guarded('profession', 'p.profession_id = ANY($#::int[])', f.profession_id);
  if (f.occupation_type_id) guarded('profession', 'p.occupation_type_id = ANY($#::int[])', f.occupation_type_id);
  if (f.marital_status_id) guarded('marital_status', 'p.marital_status_id = ANY($#::int[])', f.marital_status_id);
  if (f.complexion_id) guarded('complexion', 'p.complexion_id = ANY($#::int[])', f.complexion_id);
  if (f.religion_id) guarded('religion', 'p.religion_id = ANY($#::int[])', f.religion_id);
  if (f.mother_tongue_id) guarded('mother_tongue', 'p.mother_tongue_id = ANY($#::int[])', f.mother_tongue_id);
  if (f.food_habit_id) guarded('food_habit', 'p.food_habit_id = ANY($#::int[])', f.food_habit_id);
  if (f.language_id) {
    guarded(
      'known_languages',
      'EXISTS (SELECT 1 FROM profile_languages pl WHERE pl.profile_id = p.id AND pl.language_id = ANY($#::int[]))',
      f.language_id,
    );
  }
  if (f.zodiac_id) guarded('star_rasi', 'p.zodiac_id = ANY($#::int[])', f.zodiac_id);
  if (f.nakshatram_id) guarded('star_rasi', 'p.nakshatram_id = ANY($#::int[])', f.nakshatram_id);
  if (f.nri === 'true') guarded('work_location', 'p.is_nri = TRUE');
  if (f.nri === 'false') guarded('work_location', 'p.is_nri = FALSE');
  if (f.country_id) guarded('work_location', 'p.is_nri = TRUE AND p.nri_country_id = ANY($#::int[])', f.country_id);
  if (f.work_country_id) guarded('work_location', 'p.work_country_id = ANY($#::int[])', f.work_country_id);
  // "Place" matches where the person works/lives and the native city. All
  // three are on request (SPEC §9.8): matching never reveals a value, it
  // only keeps profiles findable by the place families ask about.
  if (f.city) {
    const like = `%${f.city}%`;
    add('(p.work_place ILIKE $# OR p.nri_place ILIKE $# OR p.city ILIKE $#)', like, like, like);
  }
  if (f.q) {
    const like = `%${f.q}%`;
    const byName = `(p.full_name ILIKE $# AND ${visibleSql('name', viewer)})`;
    // The profile ID is owner-side only (SPEC §9.18 C): admins search every
    // ID, an agent the IDs of their own uploads, a customer none.
    if (viewer.seeAll) add(`(${byName} OR p.profile_code ILIKE $#)`, like, like);
    else if (viewer.ownerAgentId) {
      add(`(${byName} OR (p.uploaded_by = ${Number(viewer.ownerAgentId)} AND p.profile_code ILIKE $#))`, like, like);
    } else add(byName, like);
  }
}
