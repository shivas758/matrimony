import { randomBytes } from 'node:crypto';
import { mkdir, unlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';
import { config } from './config.js';

const MAX_DIMENSION = 1280;
const JPEG_QUALITY = 80;

export const uploadsRoot = path.resolve(config.uploadsDir);

/** Absolute path for a stored relative file_path; null if it escapes uploads/. */
export function resolveStoredPath(relPath) {
  const abs = path.resolve(uploadsRoot, relPath);
  if (abs !== uploadsRoot && !abs.startsWith(uploadsRoot + path.sep)) return null;
  return abs;
}

/**
 * Resizes to max 1280px / JPEG 80% (SPEC §6) and stores under
 * uploads/profiles/<profileId>/<random>.jpg. Returns the relative path.
 */
export async function storeProfilePhoto(profileId, buffer) {
  const relDir = path.join('profiles', String(profileId));
  await mkdir(path.join(uploadsRoot, relDir), { recursive: true });

  const name = `${Date.now()}-${randomBytes(6).toString('hex')}.jpg`;
  const relPath = path.join(relDir, name).split(path.sep).join('/');

  const jpeg = await sharp(buffer)
    .rotate() // honour EXIF orientation before stripping metadata
    .resize({ width: MAX_DIMENSION, height: MAX_DIMENSION, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: JPEG_QUALITY, mozjpeg: true })
    .toBuffer();

  await writeFile(path.join(uploadsRoot, relPath), jpeg);
  return relPath;
}

export async function deleteStoredPhoto(relPath) {
  const abs = resolveStoredPath(relPath);
  if (!abs) return;
  try {
    await unlink(abs);
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
}

/**
 * Watermarked copy for shares, downloads and public pages.
 * Never call the un-watermarked path for anything leaving the app.
 */
export async function watermarkedBuffer(relPath, label) {
  const abs = resolveStoredPath(relPath);
  if (!abs) throw new Error('invalid photo path');

  const base = sharp(abs).rotate().resize({ width: 1080, height: 1080, fit: 'inside', withoutEnlargement: true });
  const { width = 1080, height = 1080 } = await base.metadata();

  const text = escapeXml(label || 'Shared privately');
  const fontSize = Math.max(16, Math.round(width / 28));
  const barHeight = Math.round(fontSize * 2.2);
  const svg = Buffer.from(
    `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
       <rect x="0" y="${height - barHeight}" width="${width}" height="${barHeight}" fill="rgba(0,0,0,0.45)"/>
       <text x="${Math.round(width / 2)}" y="${height - Math.round(barHeight / 2)}"
             font-family="DejaVu Sans, Arial, sans-serif" font-size="${fontSize}" fill="#ffffff"
             text-anchor="middle" dominant-baseline="central">${text}</text>
       <text x="${Math.round(width / 2)}" y="${Math.round(height / 2)}"
             font-family="DejaVu Sans, Arial, sans-serif" font-size="${fontSize * 1.6}" fill="rgba(255,255,255,0.20)"
             text-anchor="middle" dominant-baseline="central" transform="rotate(-30 ${Math.round(width / 2)} ${Math.round(height / 2)})">${text}</text>
     </svg>`,
  );

  return base.composite([{ input: svg, top: 0, left: 0 }]).jpeg({ quality: 82 }).toBuffer();
}

export function escapeXml(s) {
  return String(s).replace(/[<>&'"]/g, (c) =>
    ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' })[c],
  );
}
