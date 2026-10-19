// Generates the MILI app logo and every Android icon size from the supplied
// brand artwork (SPEC §9.17).
//
//   cd customer_app && node tool/gen_logo.mjs
//
// Source: assets/logo/mili_source.jpg — a cream tile with a peach glow
// carrying the gold interlocked rings, the wordmark MILI (wine) and
// MATRIMONY beneath, on a light grey canvas. The artwork is "keyed": the
// glow behind the ink is estimated (normalised convolution of the non-ink
// pixels) and every edge pixel is un-mixed from it, so the rings and letters
// come out on transparency with clean edges. They are then re-composed on a
// vector cream tile, so every size is rendered from geometry, not upscaled.
//
// Outputs
//   assets/logo/logo.png, logo_1024.png       full logo on its rounded tile (in-app, large)
//   assets/logo/logo_mark.png                 rings + MILI on the tile (in-app, small sizes)
//   android/.../mipmap-*/ic_launcher.png      legacy launcher icon (rings + MILI tile)
//   android/.../mipmap-*/ic_launcher_{background,foreground}.png
//                                             adaptive icon layers (API 26+)
//   android/.../drawable-*/launch_logo.png    native splash image (full logo tile)
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
const SRC = path.join(logoDir, 'mili_source.jpg');

// The tile inside the source canvas (measured; the canvas is 1408 × 768).
const TILE = { left: 429, top: 105, width: 551, height: 557 };

// Glow stops sampled from the source, centre → tile edge. Mirrored as the
// palette's peach / cream in lib/ui/theme.dart.
const GLOW = [
  [0, '#FBD4C2'],
  [0.36, '#FDDECC'],
  [0.6, '#FEE8D7'],
  [0.84, '#FFF0DD'],
  [1, '#FCF4E1'],
];

const SIZE = 1024;

// ---------------------------------------------------------------- 1. key the ink out

/** Gold or wine — never the cream/peach ground (its blue never drops below ~190). */
const isInk = (r, g, b) => (b < 175 && r - b > 55) || g < 150;

/** Three box-blur passes (≈ Gaussian) of a single-channel float image. */
function blur(src, w, h, radius) {
  let a = Float32Array.from(src);
  let b = new Float32Array(a.length);
  for (let pass = 0; pass < 3; pass++) {
    for (let y = 0; y < h; y++) {
      let acc = 0;
      for (let x = -radius; x <= radius; x++) acc += a[y * w + Math.min(w - 1, Math.max(0, x))];
      for (let x = 0; x < w; x++) {
        b[y * w + x] = acc / (2 * radius + 1);
        acc += a[y * w + Math.min(w - 1, x + radius + 1)] - a[y * w + Math.max(0, x - radius)];
      }
    }
    for (let x = 0; x < w; x++) {
      let acc = 0;
      for (let y = -radius; y <= radius; y++) acc += b[Math.min(h - 1, Math.max(0, y)) * w + x];
      for (let y = 0; y < h; y++) {
        a[y * w + x] = acc / (2 * radius + 1);
        acc += b[Math.min(h - 1, y + radius + 1) * w + x] - b[Math.max(0, y - radius) * w + x];
      }
    }
  }
  return a;
}

/** Grows (or with `shrink`, erodes) a 0/1 mask by `r` pixels (square structuring element). */
function morph(mask, w, h, r, shrink = false) {
  const out = new Uint8Array(mask.length);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let hit = shrink ? 1 : 0;
      for (let dy = -r; dy <= r && hit === (shrink ? 1 : 0); dy++) {
        for (let dx = -r; dx <= r; dx++) {
          const xx = Math.min(w - 1, Math.max(0, x + dx));
          const yy = Math.min(h - 1, Math.max(0, y + dy));
          const v = mask[yy * w + xx];
          if (shrink ? !v : v) {
            hit = shrink ? 0 : 1;
            break;
          }
        }
      }
      out[y * w + x] = hit;
    }
  }
  return out;
}

/**
 * The tile's ink on transparency: `{ rgba, width, height, rows }` where `rows`
 * are the ink bands top to bottom (rings, MILI, MATRIMONY) as [top, bottom].
 */
async function keyInk() {
  const { data, info } = await sharp(SRC).extract(TILE).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width: w, height: h } = info;
  const n = w * h;
  const ink = new Uint8Array(n);
  for (let i = 0; i < n; i++) ink[i] = isInk(data[i * 3], data[i * 3 + 1], data[i * 3 + 2]) ? 1 : 0;
  const fringe = morph(ink, w, h, 3); // ink + its anti-aliased edge
  const core = morph(ink, w, h, 1, true); // safely inside a stroke

  // The glow behind the ink: average of the nearby non-ink pixels.
  const ground = Float32Array.from(fringe, (v) => 1 - v);
  const weight = blur(ground, w, h, 14);
  const bg = [0, 1, 2].map((c) => {
    const ch = new Float32Array(n);
    for (let i = 0; i < n; i++) ch[i] = data[i * 3 + c] * ground[i];
    const sum = blur(ch, w, h, 14);
    for (let i = 0; i < n; i++) sum[i] = weight[i] > 1e-4 ? sum[i] / weight[i] : 250;
    return sum;
  });

  // Representative ink colours (gold ring, wine letters) to un-mix edges against.
  const INKS = [
    [200, 160, 86],
    [99, 30, 42],
  ];
  const rgba = Buffer.alloc(n * 4);
  for (let i = 0; i < n; i++) {
    const p = [data[i * 3], data[i * 3 + 1], data[i * 3 + 2]];
    let alpha = 0;
    if (core[i]) {
      alpha = 1;
    } else if (fringe[i]) {
      const b = [bg[0][i], bg[1][i], bg[2][i]];
      for (const k of INKS) {
        const d = [k[0] - b[0], k[1] - b[1], k[2] - b[2]];
        const t = ((p[0] - b[0]) * d[0] + (p[1] - b[1]) * d[1] + (p[2] - b[2]) * d[2]) / (d[0] ** 2 + d[1] ** 2 + d[2] ** 2);
        alpha = Math.max(alpha, Math.min(1, Math.max(0, t)));
      }
      if (alpha < 0.06) alpha = 0;
    }
    for (let c = 0; c < 3; c++) {
      // Un-mix: the colour that, laid over the glow at `alpha`, gives the source pixel.
      const v = alpha >= 1 || alpha === 0 ? p[c] : bg[c][i] + (p[c] - bg[c][i]) / alpha;
      rgba[i * 4 + c] = Math.round(Math.min(255, Math.max(0, v)));
    }
    rgba[i * 4 + 3] = Math.round(alpha * 255);
  }

  // Ink bands, top to bottom.
  const rows = [];
  let start = -1;
  for (let y = 0; y < h; y++) {
    let any = false;
    for (let x = 0; x < w && !any; x++) any = rgba[(y * w + x) * 4 + 3] > 40;
    if (any && start < 0) start = y;
    if (!any && start >= 0) {
      rows.push([start, y - 1]);
      start = -1;
    }
  }
  if (start >= 0) rows.push([start, h - 1]);
  return { rgba, width: w, height: h, rows };
}

/** The keyed ink between rows `top`..`bottom`, trimmed to its bounding box, as PNG. */
async function inkBand(key, top, bottom) {
  const band = await sharp(key.rgba, { raw: { width: key.width, height: key.height, channels: 4 } })
    .extract({ left: 0, top, width: key.width, height: bottom - top + 1 })
    .png()
    .toBuffer();
  return sharp(band).trim({ threshold: 1 }).png().toBuffer();
}

// ---------------------------------------------------------------- 2. the vector tile

const tileSvg = ({ rounded, glowY = 0.5 }) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">
  <defs>
    <radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="${SIZE / 2}" cy="${SIZE * glowY}" r="${SIZE / 2}">
      ${GLOW.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join('\n      ')}
    </radialGradient>
    <clipPath id="tile"><rect width="${SIZE}" height="${SIZE}" rx="${rounded ? 220 : 0}"/></clipPath>
  </defs>
  <g clip-path="url(#tile)">
    <rect width="${SIZE}" height="${SIZE}" fill="#FCF4E1"/>
    <rect width="${SIZE}" height="${SIZE}" fill="url(#glow)"/>
  </g>
</svg>`;

async function tile(rounded, glowY) {
  return sharp(Buffer.from(tileSvg({ rounded, glowY })), { density: 72 * 4 }).resize(SIZE, SIZE).png().toBuffer();
}

/** `art` scaled to `height` px and centred on `base` (a SIZE × SIZE PNG). */
async function placeCentered(base, art, height) {
  const scaled = await sharp(art).resize({ height, kernel: 'lanczos3' }).png().toBuffer();
  const meta = await sharp(scaled).metadata();
  return sharp(base)
    .composite([{ input: scaled, left: Math.round((SIZE - meta.width) / 2), top: Math.round((SIZE - meta.height) / 2) }])
    .png()
    .toBuffer();
}

/** Stacks PNG bands vertically, centred, with `gaps[i]` px between band i and i+1. */
async function stack(bands, gaps) {
  const metas = await Promise.all(bands.map((b) => sharp(b).metadata()));
  const width = Math.max(...metas.map((m) => m.width));
  const height = metas.reduce((s, m) => s + m.height, 0) + gaps.reduce((s, g) => s + g, 0);
  let top = 0;
  const layers = bands.map((input, i) => {
    const layer = { input, left: Math.round((width - metas[i].width) / 2), top };
    top += metas[i].height + (gaps[i] ?? 0);
    return layer;
  });
  return sharp({ create: { width, height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(layers)
    .png()
    .toBuffer();
}

/** Largest distance of an opaque pixel from the centre of `png`, in its own pixels. */
async function reach(png) {
  const { data, info } = await sharp(png).raw().toBuffer({ resolveWithObject: true });
  const cx = info.width / 2;
  const cy = info.height / 2;
  let max = 0;
  for (let y = 0; y < info.height; y++) {
    for (let x = 0; x < info.width; x++) {
      if (data[(y * info.width + x) * 4 + 3] > 24) max = Math.max(max, Math.hypot(x - cx, y - cy));
    }
  }
  return { max, height: info.height };
}

// ---------------------------------------------------------------- 3. render everything

const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

async function write(buf, size, file) {
  await mkdir(path.dirname(file), { recursive: true });
  await sharp(buf).resize(size, size, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toFile(file);
  console.log(`${path.relative(app, file)}  ${size}px`);
}

const key = await keyInk();
if (key.rows.length !== 3) throw new Error(`expected 3 ink bands (rings, MILI, MATRIMONY), found ${key.rows.length}`);
const [ringsRow, miliRow, wordRow] = key.rows;
const rings = await inkBand(key, ...ringsRow);
const mili = await inkBand(key, ...miliRow);
const matrimony = await inkBand(key, ...wordRow);

// Keep the source's spacing between the bands.
const gapRingsMili = miliRow[0] - ringsRow[1] - 1;
const gapMiliWord = wordRow[0] - miliRow[1] - 1;
const full = await stack([rings, mili, matrimony], [gapRingsMili, gapMiliWord]);
const short = await stack([rings, mili], [gapRingsMili]);

// Full logo tile: the artwork at the source's proportion of the tile.
const fullTile = await placeCentered(await tile(true, 0.52), full, Math.round(SIZE * ((wordRow[1] - ringsRow[0]) / TILE.height)));
// Rings + MILI tile, a little larger since MATRIMONY is gone.
const markTile = await placeCentered(await tile(true, 0.55), short, Math.round(SIZE * 0.6));
// Adaptive icon: background = full-bleed glow; foreground = rings + MILI kept
// inside the 66 dp safe circle (radius 0.305 of the 108 dp canvas).
const shortReach = await reach(short);
const fgHeight = Math.floor((SIZE * 0.3) * (shortReach.height / shortReach.max));
const transparent = await sharp({ create: { width: SIZE, height: SIZE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).png().toBuffer();
const foreground = await placeCentered(transparent, short, fgHeight);
const background = await tile(false, 0.55);

await mkdir(logoDir, { recursive: true });
await write(fullTile, 512, path.join(logoDir, 'logo.png'));
await write(fullTile, 1024, path.join(logoDir, 'logo_1024.png'));
await write(markTile, 256, path.join(logoDir, 'logo_mark.png'));

for (const [density, factor] of Object.entries(DENSITIES)) {
  const mip = path.join(res, `mipmap-${density}`);
  await write(markTile, 48 * factor, path.join(mip, 'ic_launcher.png'));
  await write(background, 108 * factor, path.join(mip, 'ic_launcher_background.png'));
  await write(foreground, 108 * factor, path.join(mip, 'ic_launcher_foreground.png'));
  await write(fullTile, 128 * factor, path.join(res, `drawable-${density}`, 'launch_logo.png'));
}
console.log('done');
