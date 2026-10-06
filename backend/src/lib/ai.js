// AI import: turns a bio-data document into a draft profile (SPEC §4,
// POST /profiles/parse). Talks to the Anthropic API with structured output.
// Nothing in this module touches the database — the agent reviews the draft
// and saves it through the normal profile endpoint.

import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
// The SDK's structured-output helper needs zod v4 schemas. The rest of the
// backend keeps zod v3; zod 3.25+ ships v4 under this subpath so both coexist.
import { z } from 'zod/v4';
import { config } from './config.js';
import { ApiError } from './errors.js';

export const isAiConfigured = () => Boolean(config.anthropicApiKey);

/** What the model returns. Everything nullable: absent means "not in the document". */
export const ExtractedProfile = z.object({
  is_biodata: z
    .boolean()
    .describe('false when the input is not a matrimony bio-data / marriage profile at all'),
  full_name: z.string().nullable(),
  gender: z
    .enum(['bride', 'groom'])
    .nullable()
    .describe("'bride' for a woman's profile, 'groom' for a man's; null if unclear"),
  dob: z
    .string()
    .nullable()
    .describe('Date of birth as YYYY-MM-DD, only when day, month and year are all present'),
  age_years: z
    .number()
    .int()
    .nullable()
    .describe('Age in years when stated; use this when a full date of birth is absent'),
  height_cm: z
    .number()
    .int()
    .nullable()
    .describe("Height in centimetres as an integer; convert feet/inches (5'6\" = 168)"),
  weight_kg: z.number().int().nullable().describe('Weight in kilograms as an integer, when stated'),
  complexion: z
    .string()
    .nullable()
    .describe('Skin complexion as written: very fair, fair, wheatish, wheatish brown, dark'),
  marital_status: z.string().nullable(),
  community: z.string().nullable().describe('Caste / community exactly as written'),
  subcaste: z.string().nullable().describe('Sub-caste if written'),
  gothram: z.string().nullable().describe('Gothram / gotra as written'),
  education: z.string().nullable().describe('Highest qualification, short, e.g. "B.Tech"'),
  education_details: z
    .string()
    .nullable()
    .describe('Extra detail about the education: branch, college, year — one line'),
  profession: z.string().nullable().describe('Occupation, short, e.g. "Software Engineer"'),
  profession_details: z
    .string()
    .nullable()
    .describe('Extra detail about the job: employer, designation — one line'),
  work_place: z.string().nullable().describe('City (and country, if abroad) where the person works or lives now'),
  work_country: z
    .string()
    .nullable()
    .describe('Country where the person works or lives now, e.g. "India", "United States"; null when not stated'),
  occupation_type: z
    .string()
    .nullable()
    .describe(
      'Kind of occupation when it can be told: private job, government job, business, self-employed, professional (doctor / lawyer / CA), farmer / agriculture, student, not working',
    ),
  income_text: z.string().nullable().describe('Income as written, e.g. "8 LPA"'),
  other_income: z.string().nullable().describe('Other / additional income as written, e.g. "rental 2 LPA"; null when not stated'),
  nationality: z.string().nullable().describe('Nationality as written, e.g. "Indian", "American"; null when not stated'),
  education_levels: z
    .array(
      z.object({
        level: z
          .enum(['below_10th', '10th', 'intermediate', 'graduation', 'post_graduation'])
          .describe('Which stage of education this entry is'),
        details: z.string().nullable().describe('School / board / degree / college / year for that stage, one line'),
        country: z.string().nullable().describe('Country where that stage was studied, when stated'),
      }),
    )
    .nullable()
    .describe('Education by stage when the document lists it (10th, intermediate / 12th, graduation, post graduation); at most one entry per stage; null when only the highest qualification is given'),
  is_nri: z.boolean().nullable().describe('true when the person lives or works outside India'),
  nri_country: z.string().nullable().describe('Country abroad when is_nri, as written'),
  nri_place: z.string().nullable().describe('City / state abroad when is_nri, as written'),
  city: z.string().nullable().describe('Native place: home town / village of the family'),
  state: z.string().nullable().describe('State of the native place'),
  zodiac: z.string().nullable().describe('Rasi / rashi / zodiac / moon sign as written'),
  nakshatram: z.string().nullable().describe('Star / nakshatra(m) as written'),
  birth_time: z
    .string()
    .nullable()
    .describe('Time of birth as HH:MM in 24-hour form (10.30 PM → "22:30"); null when not stated'),
  birth_place: z
    .string()
    .nullable()
    .describe('Place of birth as written (town / city). Separate from the native place'),
  birth_state: z.string().nullable().describe('State of the place of birth, when stated'),
  birth_country: z.string().nullable().describe('Country of the place of birth, when stated'),
  religion: z.string().nullable().describe('Religion as written, e.g. Hindu, Muslim, Christian'),
  mother_tongue: z.string().nullable().describe('Mother tongue as written, e.g. Telugu'),
  known_languages: z
    .array(z.string())
    .nullable()
    .describe('Languages the person speaks or knows, as written, one per entry'),
  food_habit: z
    .string()
    .nullable()
    .describe('Diet as written: vegetarian, non-vegetarian, eggetarian, fish only, jain, vegan'),
  has_siblings: z
    .boolean()
    .nullable()
    .describe('true when siblings are mentioned, false when the document says there are none, null when not stated'),
  siblings_count: z
    .number()
    .int()
    .nullable()
    .describe('Total number of siblings when stated or countable from the text'),
  siblings_details: z
    .string()
    .nullable()
    .describe('One line about the siblings, e.g. "1 elder brother, married, software engineer in Pune". No phone numbers'),
  elder_sisters: z.number().int().nullable().describe('Number of elder sisters when stated or countable'),
  younger_sisters: z.number().int().nullable().describe('Number of younger sisters when stated or countable'),
  elder_brothers: z.number().int().nullable().describe('Number of elder brothers when stated or countable'),
  younger_brothers: z.number().int().nullable().describe('Number of younger brothers when stated or countable'),
  property_share: z
    .string()
    .nullable()
    .describe('The share of family property that comes to the person, as written, e.g. "half share in 5 acres"'),
  property_details: z
    .string()
    .nullable()
    .describe('Family property / assets as written, 1-2 lines, no addresses'),
  about: z
    .string()
    .nullable()
    .describe('Brief third-person description of the person, 1-3 sentences, no contact details'),
  family_details: z
    .string()
    .nullable()
    .describe('Parents, siblings, family background, 1-3 sentences, no contact details'),
  father_name: z.string().nullable().describe("Father's name"),
  father_occupation: z.string().nullable().describe("Father's occupation, short, e.g. \"Retired teacher\""),
  father_phone: z.string().nullable().describe("Father's phone number, digits and + only"),
  mother_name: z.string().nullable().describe("Mother's name"),
  mother_occupation: z.string().nullable().describe("Mother's occupation, short, e.g. \"Homemaker\""),
  mother_phone: z.string().nullable().describe("Mother's phone number, digits and + only"),
  contact_name: z.string().nullable().describe('Name of the contact person, often a parent'),
  contact_phone: z.string().nullable().describe('Phone number to reach the family, digits and + only'),
});

const SYSTEM = `You extract structured fields from Indian matrimony bio-data documents (a PDF, a photo of a printed or handwritten bio-data, or pasted text) for a marriage bureau's records.

Rules:
- Copy values as written. Never invent or guess; use null for anything the document does not state.
- dob only when the complete date is present. Otherwise leave dob null and fill age_years if an age is given.
- Heights such as 5'6", 5.6 ft, 168 cms → height_cm as an integer in centimetres.
- "Caste" or "Community" → community. "Sub caste" / "Sub-caste" → subcaste. "Gothram" / "Gotra" → gothram. "Star" / "Nakshatra(m)" → nakshatram. "Rasi" / "Rashi" / "Zodiac" / "Moon sign" → zodiac.
- "Time of birth" / "Birth time" / "TOB" → birth_time as HH:MM in 24-hour form (4.35 AM → 04:35, 10.30 PM → 22:30). "Place of birth" / "Birth place" / "POB" → birth_place. These are horoscope details and are separate from the native place.
- education: the qualification itself, short. Anything more (branch, college, year) → education_details. Same split for profession / profession_details (employer, designation).
- When the document lists education stage by stage (10th / SSC, Intermediate / 12th / HSC, Graduation / degree, Post graduation / masters) → education_levels, one entry per stage with its details and the country when stated. A single highest qualification alone → education only.
- Kind of job (private, government, business, self-employed, professional, farmer, student, not working) → occupation_type. "Other income" / "additional income" / rental / agricultural income → other_income.
- "Nationality" → nationality (e.g. Indian). "Native place" / "Native" / "Hometown" / "Village" → city (and state). Where the person currently works or lives → work_place, and its country → work_country ("India" when the place is in India).
- "Place of birth" may carry a state and a country → birth_state, birth_country.
- Living or working abroad (USA, UK, Gulf, Australia …) → is_nri true, nri_country, nri_place. Otherwise is_nri false.
- Weight such as 62 kgs → weight_kg. Complexion words (fair, wheatish, dark …) → complexion.
- gender: 'bride' when the document is for a woman (daughter, bride, she/her), 'groom' for a man (son, groom, he/him).
- "Religion" → religion. "Mother tongue" → mother_tongue. "Languages known" / "Speaks" → known_languages (one entry per language). "Diet" / "Food" / "Eating habits" → food_habit.
- Siblings: "no siblings" / "only child" → has_siblings false. Any brother/sister mentioned → has_siblings true, siblings_count = how many, siblings_details = one line about them, and elder_sisters / younger_sisters / elder_brothers / younger_brothers when the document says who is elder or younger. Nothing said → all null.
- about and family_details: brief, factual, third person. Never put phone numbers or addresses in them.
- Property / assets / land / houses of the family → property_details; the person's share of it, when stated → property_share. No addresses.
- Parents' names → father_name / mother_name; their occupations → father_occupation / mother_occupation; their numbers → father_phone / mother_phone (digits and a leading + only).
- contact_phone: the family's phone number; keep digits and a leading + only.
- If the input is clearly not a matrimony bio-data, set is_biodata to false and leave every other field null.`;

const MEDIA_KIND = {
  'application/pdf': 'document',
  'image/jpeg': 'image',
  'image/png': 'image',
  'image/webp': 'image',
  'image/gif': 'image',
};

/**
 * Sends the document to the model and returns the validated extraction.
 * @param {{ text?: string, file?: { buffer: Buffer, mimetype: string } }} input
 */
export async function extractProfile(input) {
  if (!isAiConfigured()) {
    throw new ApiError(503, 'ai_not_configured', 'AI import is not set up on this server');
  }

  const content = [];
  if (input.file) {
    const kind = MEDIA_KIND[input.file.mimetype];
    const data = input.file.buffer.toString('base64');
    if (kind === 'document') {
      content.push({ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data } });
    } else if (kind === 'image') {
      content.push({ type: 'image', source: { type: 'base64', media_type: input.file.mimetype, data } });
    } else {
      content.push({ type: 'text', text: input.file.buffer.toString('utf8') });
    }
  }
  if (input.text) content.push({ type: 'text', text: input.text });
  content.push({ type: 'text', text: 'Extract the profile fields from the bio-data above.' });

  const client = new Anthropic({ apiKey: config.anthropicApiKey });
  const response = await client.messages.parse({
    model: config.claudeModel,
    max_tokens: 16000,
    system: SYSTEM,
    // Extraction is routine work: medium effort keeps it accurate without long thinking.
    output_config: { effort: 'medium', format: zodOutputFormat(ExtractedProfile) },
    messages: [{ role: 'user', content }],
  });

  if (response.stop_reason === 'refusal') {
    throw new ApiError(422, 'ai_refused', 'The AI declined to process this document');
  }
  if (response.stop_reason === 'max_tokens' || !response.parsed_output) {
    throw new ApiError(422, 'unreadable_document', 'Could not read a profile from this document');
  }

  return {
    data: response.parsed_output,
    model: response.model,
    usage: {
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
    },
  };
}

/** Maps SDK exceptions to API errors with stable codes, most specific first. */
export function mapAiError(err) {
  if (err instanceof ApiError) return err;
  if (err instanceof Anthropic.AuthenticationError) {
    return new ApiError(503, 'ai_not_configured', 'The AI key configured on this server is invalid');
  }
  if (err instanceof Anthropic.RateLimitError) {
    return new ApiError(503, 'ai_busy', 'AI import is busy right now — try again in a minute');
  }
  if (err instanceof Anthropic.BadRequestError) {
    return new ApiError(422, 'unreadable_document', 'This file could not be processed');
  }
  if (err instanceof Anthropic.APIError) {
    return new ApiError(502, 'ai_error', 'AI import failed — please try again');
  }
  return err;
}
