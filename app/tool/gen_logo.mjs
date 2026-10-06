// Generates the Mediator app logo and every Android icon size from the
// supplied brand artwork.
//
//   cd app && node tool/gen_logo.mjs
//
// Source: assets/logo/mediator_source.jpg — the low-resolution brand image
// (heart with the couple and the handshake, plus the wordmark). Only the ICON
// is used: the wordmark below it is cropped away. The icon is separated from
// its navy background by colour keying (gold/red/white on dark blue), lightly
// denoised, upscaled with Lanczos and sharpened, then composited onto a crisp,
// vector-drawn navy tile — so the tile edges, gradient and corners are sharp at
// every size and only the artwork itself is upscaled.
//
// Outputs
//   assets/logo/logo.png                      512 px tile, used in-app (splash, login)
//   assets/logo/logo_mark.png                 icon only on transparent, 512 px
//   assets/logo/logo_1024.png                 1024 px tile (store listings, docs)
//   android/.../mipmap-*/ic_launcher.png      legacy launcher icon
//   android/.../mipmap-*/ic_launcher_{background,foreground,monochrome}.png
//                                             adaptive icon layers (API 26+)
//   android/.../drawable-*/launch_logo.png    native splash image
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
const SRC = path.join(logoDir, 'mediator_source.jpg');

// ---------------------------------------------------------------- brand colours
// Sampled from the artwork; also mirrored in app/lib/ui/theme.dart.
const NAVY_DEEP = '#081C33';
const NAVY = '#0F2F52';
const NAVY_LIGHT = '#1B4F82';

// ---------------------------------------------------------------- 1. key the icon out

// Region of the source that holds the icon (heart + sparkle), excluding the
// wordmark and the image's own light border.
const CROP = { left: 58, top: 8, width: 320, height: 262 };

/**
 * Returns the icon as an RGBA PNG buffer at source resolution. Alpha comes
 * from "warmth": gold and red have red well above blue, the sparkle is near
 * white; the navy background and its blue glow have blue above red.
 */
async function extractIcon() {
  const { data, info } = await sharp(SRC)
    .extract(CROP)
    .median(3) // knock down JPEG blocking before we magnify it
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width: W, height: H } = info;
  const rgba = Buffer.alloc(W * H * 4);
  for (let p = 0; p < W * H; p++) {
    const r = data[p * 3];
    const g = data[p * 3 + 1];
    const b = data[p * 3 + 2];
    const warm = clamp01((r - b - 12) / 40);
    const white = clamp01((Math.min(r, g, b) - 175) / 45);
    const a = Math.max(warm, white);
    rgba[p * 4] = r;
    rgba[p * 4 + 1] = g;
    rgba[p * 4 + 2] = b;
    rgba[p * 4 + 3] = Math.round(a * 255);
  }
  // Trim to the artwork's own bounding box so centring is exact.
  return sharp(rgba, { raw: { width: W, height: H, channels: 4 } }).png().trim({ threshold: 8 }).toBuffer();
}

const clamp01 = (v) => Math.max(0, Math.min(1, v));

/** Upscales the keyed icon so its longer side is `size` px, with a little sharpening. */
async function iconAt(iconPng, size) {
  return sharp(iconPng)
    .resize(size, size, { fit: 'inside', kernel: 'lanczos3' })
    .sharpen({ sigma: 1.1, m1: 0.6, m2: 0.4 })
    .png()
    .toBuffer();
}

/** Black silhouette of the icon (alpha only) for the monochrome launcher layer. */
async function iconMono(iconPng, size) {
  const scaled = await iconAt(iconPng, size);
  const alpha = await sharp(scaled).ensureAlpha().extractChannel(3).toBuffer();
  const { width, height } = await sharp(scaled).metadata();
  return sharp({ create: { width, height, channels: 3, background: '#000000' } })
    .joinChannel(alpha)
    .png()
    .toBuffer();
}

// ---------------------------------------------------------------- 2. the vector tile

const SIZE = 1024;

const tileSvg = ({ rounded }) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <radialGradient id="bg" cx="0.5" cy="0.42" r="0.75">
      <stop offset="0" stop-color="${NAVY_LIGHT}"/>
      <stop offset="0.55" stop-color="${NAVY}"/>
      <stop offset="1" stop-color="${NAVY_DEEP}"/>
    </radialGradient>
    <radialGradient id="glow" cx="0.5" cy="0.47" r="0.42">
      <stop offset="0" stop-color="#F3D27A" stop-opacity="0.32"/>
      <stop offset="0.6" stop-color="#F3D27A" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#F3D27A" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.10"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <clipPath id="tile"><rect width="${SIZE}" height="${SIZE}" rx="${rounded ? 230 : 0}"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect width="${SIZE}" height="${SIZE}" fill="url(#bg)"/>
    <rect width="${SIZE}" height="${SIZE}" fill="url(#glow)"/>
    <rect width="${SIZE}" height="${SIZE}" fill="url(#gloss)"/>
  </g>
</svg>`;

const transparentSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}"/>`;

/** Composites `icon` (PNG buffer) centred on a 1024 canvas described by `svg`. */
async function compose(svg, icon) {
  const meta = await sharp(icon).metadata();
  return sharp(Buffer.from(svg), { density: 72 * 4 })
    .resize(SIZE, SIZE)
    .composite([
      {
        input: icon,
        left: Math.round((SIZE - meta.width) / 2),
        // Sit a touch above centre: the sparkle makes the artwork top-heavy.
        top: Math.round((SIZE - meta.height) / 2) - 6,
      },
    ])
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

const icon = await extractIcon();

// Tile: icon fills ~70% of the width. Adaptive foreground: ~58%, inside the
// 66/108 safe zone. Mark: icon alone, ~90% of the canvas.
const full = await compose(tileSvg({ rounded: true }), await iconAt(icon, 720));
const background = await sharp(Buffer.from(tileSvg({ rounded: false })), { density: 72 * 4 })
  .resize(SIZE, SIZE)
  .png()
  .toBuffer();
const foreground = await compose(transparentSvg, await iconAt(icon, 600));
const monochrome = await compose(transparentSvg, await iconMono(icon, 600));
const mark = await compose(transparentSvg, await iconAt(icon, 920));

await mkdir(logoDir, { recursive: true });
await write(full, 512, path.join(logoDir, 'logo.png'));
await write(mark, 512, path.join(logoDir, 'logo_mark.png'));
await write(full, 1024, path.join(logoDir, 'logo_1024.png'));

for (const [density, factor] of Object.entries(DENSITIES)) {
  const mip = path.join(res, `mipmap-${density}`);
  await write(full, 48 * factor, path.join(mip, 'ic_launcher.png'));
  await write(background, 108 * factor, path.join(mip, 'ic_launcher_background.png'));
  await write(foreground, 108 * factor, path.join(mip, 'ic_launcher_foreground.png'));
  await write(monochrome, 108 * factor, path.join(mip, 'ic_launcher_monochrome.png'));
  await write(full, 96 * factor, path.join(res, `drawable-${density}`, 'launch_logo.png'));
}
console.log('done');
