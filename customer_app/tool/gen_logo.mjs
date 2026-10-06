// Generates the Gandharva app logo and every Android icon size from the
// supplied brand artwork.
//
//   cd customer_app && node tool/gen_logo.mjs
//
// Source: assets/logo/gandharva_source.jpg — the maroon disc (couple, lotus
// heart, wordmark and tagline) on a black square. The disc is found by
// trimming the black border, then cut out with a circular mask so the black
// corners never show; only the disc itself is scaled. The adaptive launcher
// icon puts the disc on a vector maroon tile so the tile edges stay crisp.
//
// Outputs
//   assets/logo/logo.png                      512 px disc on transparent (in-app)
//   assets/logo/logo_1024.png                 1024 px disc (store listings, docs)
//   android/.../mipmap-*/ic_launcher.png      legacy launcher icon (disc on maroon tile)
//   android/.../mipmap-*/ic_launcher_{background,foreground}.png
//                                             adaptive icon layers (API 26+)
//   android/.../drawable-*/launch_logo.png    native splash image (disc)
//
// Uses the backend's `sharp` install so nothing new has to be installed.
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from '../../backend/node_modules/sharp/lib/index.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');
const res = path.join(app, 'android', 'app', 'src', 'main', 'res');
const logoDir = path.join(app, 'assets', 'logo');
const SRC = path.join(logoDir, 'gandharva_source.jpg');

// Brand colours — mirrored in lib/ui/theme.dart and the backend registration form.
const MAROON_DEEP = '#2E0F18';
const MAROON = '#4A1A29';
const MAROON_LIGHT = '#6B2A3D';

const SIZE = 1024;

// ---------------------------------------------------------------- 1. cut the disc out

/** The disc as a square RGBA PNG (SIZE px) with everything outside the circle transparent. */
async function extractDisc() {
  // Trim the black border, then square up and scale to SIZE.
  const trimmed = await sharp(SRC).trim({ background: '#000000', threshold: 40 }).toBuffer();
  const meta = await sharp(trimmed).metadata();
  const side = Math.min(meta.width, meta.height);
  const square = await sharp(trimmed)
    .extract({
      left: Math.round((meta.width - side) / 2),
      top: Math.round((meta.height - side) / 2),
      width: side,
      height: side,
    })
    .resize(SIZE, SIZE, { kernel: 'lanczos3' })
    .toBuffer();
  // Circular mask a hair inside the rim so no dark edge pixels survive.
  const mask = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}">
       <circle cx="${SIZE / 2}" cy="${SIZE / 2}" r="${SIZE / 2 - 3}" fill="#fff"/>
     </svg>`,
  );
  return sharp(square)
    .ensureAlpha()
    .composite([{ input: mask, blend: 'dest-in' }])
    .png()
    .toBuffer();
}

/** Disc scaled so it fills `size` px, centred on a SIZE canvas. */
async function discAt(disc, size) {
  const scaled = await sharp(disc).resize(size, size, { kernel: 'lanczos3' }).png().toBuffer();
  return sharp({ create: { width: SIZE, height: SIZE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: scaled, left: Math.round((SIZE - size) / 2), top: Math.round((SIZE - size) / 2) }])
    .png()
    .toBuffer();
}

// ---------------------------------------------------------------- 2. the vector tile

const tileSvg = ({ rounded }) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <radialGradient id="bg" cx="0.5" cy="0.42" r="0.75">
      <stop offset="0" stop-color="${MAROON_LIGHT}"/>
      <stop offset="0.55" stop-color="${MAROON}"/>
      <stop offset="1" stop-color="${MAROON_DEEP}"/>
    </radialGradient>
    <clipPath id="tile"><rect width="${SIZE}" height="${SIZE}" rx="${rounded ? 230 : 0}"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>
  </g>
</svg>`;

async function tile(rounded) {
  return sharp(Buffer.from(tileSvg({ rounded })), { density: 72 * 4 }).resize(SIZE, SIZE).png().toBuffer();
}

async function onTile(rounded, discPng, size) {
  const base = await tile(rounded);
  const scaled = await sharp(discPng).resize(size, size, { kernel: 'lanczos3' }).png().toBuffer();
  return sharp(base)
    .composite([{ input: scaled, left: Math.round((SIZE - size) / 2), top: Math.round((SIZE - size) / 2) }])
    .png()
    .toBuffer();
}

// ---------------------------------------------------------------- 3. render everything

const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

async function write(buf, size, file) {
  await mkdir(path.dirname(file), { recursive: true });
  await sharp(buf).resize(size, size, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toFile(file);
  console.log(`${path.relative(app, file)}  ${size}px`);
}

const disc = await extractDisc();

const mark = await discAt(disc, SIZE);              // in-app + splash: the disc alone
const legacy = await onTile(true, disc, 880);       // legacy launcher: disc on a rounded maroon tile
const background = await tile(false);               // adaptive background layer
const foreground = await discAt(disc, 640);         // adaptive foreground: inside the 66/108 safe zone

await mkdir(logoDir, { recursive: true });
await write(mark, 512, path.join(logoDir, 'logo.png'));
await write(mark, 1024, path.join(logoDir, 'logo_1024.png'));

for (const [density, factor] of Object.entries(DENSITIES)) {
  const mip = path.join(res, `mipmap-${density}`);
  await write(legacy, 48 * factor, path.join(mip, 'ic_launcher.png'));
  await write(background, 108 * factor, path.join(mip, 'ic_launcher_background.png'));
  await write(foreground, 108 * factor, path.join(mip, 'ic_launcher_foreground.png'));
  await write(mark, 96 * factor, path.join(res, `drawable-${density}`, 'launch_logo.png'));
}
console.log('done');
