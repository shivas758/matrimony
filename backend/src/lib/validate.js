import { z } from 'zod';
import { badRequest } from './errors.js';

/** Parses `data` with a zod schema, throwing a 400 ApiError on failure. */
export function parse(schema, data) {
  const result = schema.safeParse(data);
  if (!result.success) {
    const details = result.error.issues.map((i) => ({
      field: i.path.join('.') || '(root)',
      message: i.message,
    }));
    throw badRequest('validation_failed', 'Invalid input', details);
  }
  return result.data;
}

/**
 * Indian mobile number: 10 digits starting 6-9.
 * A +91 / 91 / 0 prefix is stripped ONLY when a full 10-digit number follows it —
 * a bare 10-digit number like 9123456789 must keep its leading "91".
 */
export const phoneSchema = z
  .string()
  .trim()
  .transform((s) => {
    const d = s.replace(/[\s-]/g, '');
    if (/^\+91\d{10}$/.test(d)) return d.slice(3);
    if (/^91\d{10}$/.test(d)) return d.slice(2);
    if (/^0\d{10}$/.test(d)) return d.slice(1);
    return d;
  })
  .pipe(z.string().regex(/^[6-9]\d{9}$/, 'Enter a valid 10-digit mobile number'));

export const passwordSchema = z
  .string()
  .min(6, 'Password must be at least 6 characters')
  .max(100);

/** Comma-separated or repeated query param -> array of positive ints. */
export const idListQuery = z
  .union([z.string(), z.array(z.string())])
  .optional()
  .transform((v) => {
    if (v === undefined) return undefined;
    const parts = (Array.isArray(v) ? v : [v]).flatMap((s) => String(s).split(','));
    const ids = parts.map((s) => Number(s.trim())).filter((n) => Number.isInteger(n) && n > 0);
    return ids.length ? [...new Set(ids)] : undefined;
  });

/**
 * Optional integer query param. Every consumer binds the value to an int /
 * bigint parameter (OFFSET, make_interval, id columns), so it must be a whole
 * number within the safe range — `1.05` or `1e300` would otherwise pass zod
 * and blow up in Postgres as a 500 instead of a 400 (SPEC §6: validate with zod).
 */
export const intQuery = (min, max) =>
  z
    .union([z.string(), z.number()])
    .optional()
    .transform((v) => (v === undefined || v === '' ? undefined : Number(v)))
    .refine(
      (n) =>
        n === undefined ||
        (Number.isInteger(n) &&
          Math.abs(n) <= Number.MAX_SAFE_INTEGER &&
          (min === undefined || n >= min) &&
          (max === undefined || n <= max)),
      { message: `Must be a whole number${min !== undefined ? ` >= ${min}` : ''}${max !== undefined ? ` <= ${max}` : ''}` },
    );
