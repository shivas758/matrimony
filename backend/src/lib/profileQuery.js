// Profile list filters shared by the agent list (GET /profiles, SPEC §4) and
// the customer list (GET /customer/profiles, SPEC §9.9). Only the search
// filters live here — visibility, `mine` and `status` stay in the routes,
// because who may see what differs between agents and customers.

import { z } from 'zod';
import { badRequest } from './errors.js';
import { idListQuery, intQuery } from './validate.js';

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
  q: z.string().trim().max(80).optional(),
  status: z.enum(['active', 'engaged', 'married', 'hidden', 'on_hold']).optional(),
  mine: z.enum(['true', 'false']).optional(),
  sort: z.enum(['newest', 'oldest', 'name', 'age_asc', 'age_desc']).default('newest'),
  page: intQuery(1).default(1),
  limit: intQuery(1, 100).default(20),
});

export const SORTS = {
  newest: 'p.created_at DESC, p.id DESC',
  oldest: 'p.created_at ASC, p.id ASC',
  name: 'p.full_name ASC, p.id ASC',
  age_asc: 'p.dob DESC, p.id ASC',
  age_desc: 'p.dob ASC, p.id ASC',
};

/**
 * Adds the search filters of a parsed listQuerySchema `f` through `add(sql,
 * ...vals)`, where every `$#` in `sql` becomes the next placeholder (see the
 * routes for the helper). The profiles table must be aliased `p`.
 * Not here: visibility, mine, status.
 */
export function applyListFilters(f, add) {
  if (f.age_min !== undefined && f.age_max !== undefined && f.age_min > f.age_max) {
    throw badRequest('bad_age_range', 'Minimum age cannot exceed maximum age');
  }
  if (f.gender) add('p.gender = $#', f.gender);
  // Age -> dob range so the (gender, dob) index stays usable.
  if (f.age_min !== undefined) add('p.dob <= (current_date - make_interval(years => $#))', f.age_min);
  if (f.age_max !== undefined) add('p.dob > (current_date - make_interval(years => $#))', f.age_max + 1);
  if (f.height_min !== undefined) add('p.height_cm >= $#', f.height_min);
  if (f.height_max !== undefined) add('p.height_cm <= $#', f.height_max);
  if (f.community_id) add('p.community_id = ANY($#::int[])', f.community_id);
  if (f.subcaste_id) add('p.subcaste_id = ANY($#::int[])', f.subcaste_id);
  if (f.education_id) add('p.education_id = ANY($#::int[])', f.education_id);
  if (f.profession_id) add('p.profession_id = ANY($#::int[])', f.profession_id);
  if (f.occupation_type_id) add('p.occupation_type_id = ANY($#::int[])', f.occupation_type_id);
  if (f.marital_status_id) add('p.marital_status_id = ANY($#::int[])', f.marital_status_id);
  if (f.complexion_id) add('p.complexion_id = ANY($#::int[])', f.complexion_id);
  if (f.religion_id) add('p.religion_id = ANY($#::int[])', f.religion_id);
  if (f.mother_tongue_id) add('p.mother_tongue_id = ANY($#::int[])', f.mother_tongue_id);
  if (f.food_habit_id) add('p.food_habit_id = ANY($#::int[])', f.food_habit_id);
  if (f.language_id) {
    add(
      'EXISTS (SELECT 1 FROM profile_languages pl WHERE pl.profile_id = p.id AND pl.language_id = ANY($#::int[]))',
      f.language_id,
    );
  }
  if (f.zodiac_id) add('p.zodiac_id = ANY($#::int[])', f.zodiac_id);
  if (f.nakshatram_id) add('p.nakshatram_id = ANY($#::int[])', f.nakshatram_id);
  if (f.nri === 'true') add('p.is_nri = TRUE');
  if (f.nri === 'false') add('p.is_nri = FALSE');
  if (f.country_id) add('p.is_nri = TRUE AND p.nri_country_id = ANY($#::int[])', f.country_id);
  if (f.work_country_id) add('p.work_country_id = ANY($#::int[])', f.work_country_id);
  // "Place" matches where the person works/lives and the native city. All
  // three are on request now (SPEC §9.8): matching never reveals a value, it
  // only keeps profiles findable by the place families ask about.
  if (f.city) {
    const like = `%${f.city}%`;
    add('(p.work_place ILIKE $# OR p.nri_place ILIKE $# OR p.city ILIKE $#)', like, like, like);
  }
  if (f.q) add('p.full_name ILIKE $#', `%${f.q}%`);
}
