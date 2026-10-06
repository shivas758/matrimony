import { Router } from 'express';
import { many } from '../lib/db.js';
import { asyncHandler } from '../lib/errors.js';

export const mastersRouter = Router();

/** Every master list in one object — shared by GET /api/masters and the public registration form. */
export async function loadMasters({ includeInactive = false } = {}) {
  const activeOnly = includeInactive ? '' : 'WHERE active = TRUE';

  const simple = (table) =>
    many(`SELECT id, name, active, sort_order FROM ${table} ${activeOnly} ORDER BY sort_order, name`);

  const [
    communities, subcastes, professions, educations, marital_statuses,
    complexions, countries, religions, languages, food_habits, occupation_types,
    zodiac_signs, nakshatrams,
  ] = await Promise.all([
    simple('communities'),
    // Subcastes carry community_id so the app can scope them to the chosen community.
    many(
      `SELECT id, community_id, name, active, sort_order FROM subcastes ${activeOnly}
       ORDER BY community_id, sort_order, name`,
    ),
    simple('professions'),
    simple('educations'),
    simple('marital_statuses'),
    simple('complexions'),
    // India first (sort 0): nationality / birth / work / education countries use this list too.
    simple('countries'),
    simple('religions'),
    // One list for both mother tongue and known languages.
    simple('languages'),
    simple('food_habits'),
    simple('occupation_types'),
    many('SELECT id, english_name, indian_name, sort_order FROM zodiac_signs ORDER BY sort_order'),
    many('SELECT id, name, sort_order FROM nakshatrams ORDER BY sort_order'),
  ]);

  return {
    communities, subcastes, professions, educations, marital_statuses,
    complexions, countries, religions, languages, food_habits, occupation_types,
    zodiac_signs, nakshatrams,
  };
}

// GET /api/masters — one payload for every dropdown in the apps (SPEC §4).
// No auth: the signup screens need the community list before a token exists.
mastersRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    // Admins editing master data need to see inactive rows too.
    const includeInactive = Boolean(req.agent?.is_admin && req.query.include_inactive === 'true');
    res.json(await loadMasters({ includeInactive }));
  }),
);
