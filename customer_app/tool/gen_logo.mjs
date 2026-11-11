// Generates the Wedbook Matrimony logo and every Android icon size from the
// supplied brand artwork (SPEC §9.18 A).
//
//   cd customer_app && node tool/gen_logo.mjs
//
// Source: assets/logo/wedbook_matrimony_source.jpg — a rounded wine tile on a
// white canvas, carrying two interlocked gold rings (with the ♂ and ♀ signs)
// and the gold serif wordmark "Wedbook" / "Matrimony".
//
// The tile is not square and its corners are baked into the white canvas, so
// it is rebuilt instead of cropped:
//   1. the tile's own wine gradient is measured (a plane fitted to the wine
//      pixels away from the gold);
//   2. the gold artwork is keyed out — every edge pixel is un-mixed from the
//      wine behind it, so the rings and letters sit on transparency without a
//      dark halo;
//   3. the gold is laid back on a square tile of the measured gradient with
//      clean rounded corners on transparency.
//
// Outputs (the file names the app already uses)
//   assets/logo/logo.png, logo_1024.png       the tile: rings + wordmark (in-app, splash)
//   assets/logo/logo_mark.png                 rings alone on the tile (in-app, small sizes)
//   android/.../mipmap-*/ic_launcher.png      legacy launcher icon (the tile)
//   android/.../mipmap-*/ic_launcher_background.png
//                                             adaptive icon: full-bleed tile wine
//   android/.../mipmap-*/ic_launcher_foreground.png
//                                             adaptive icon: rings + wordmark inside the safe zone
//   android/.../drawable-*/launch_logo.png    native splash image (the tile)
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
const SRC = path.join(logoDir, 'wedbook_matrimony_source.jpg');

// The tile inside the source canvas (measured; the canvas is 1280 × 698) and
// the radius of its corners, both in source pixels.
const TILE = { left: 372, top: 70, width: 536, height: 559 };
const TILE_RADIUS = 106;

const SIZE = 1024;
/** Corner radius of the rebuilt square tile — the source's proportion (106 / 536). */
const CORNER = Math.round(SIZE * 0.2);
/** Width of the artwork on the rebuilt tile — the source's proportion (422 / 536). */
const ART_WIDTH = 0.787;
/** Width of the rings on the rings-only tile. */
const MARK_WIDTH = 0.8;
/**
 * Adaptive icons: the launcher only guarantees the centre 66 dp of the 108 dp
 * layer, so the artwork must stay within a circle of radius 33 / 108. A little
 * less, so nothing touches the mask.
 */
const SAFE_RADIUS = (33 / 108) * 0.96;

// ---------------------------------------------------------------- helpers

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
  // Separable: rows, then columns.
  const pass = (src, horizontal) => {
    const out = new Uint8Array(src.length);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let hit = shrink ? 1 : 0;
        for (let d = -r; d <= r; d++) {
          const xx = horizontal ? Math.min(w - 1, Math.max(0, x + d)) : x;
          const yy = horizontal ? y : Math.min(h - 1, Math.max(0, y + d));
          const v = src[yy * w + xx];
          if (shrink ? !v : v) {
            hit = shrink ? 0 : 1;
            break;
          }
        }
        out[y * w + x] = hit;
      }
    }
    return out;
  };
  return pass(pass(mask, true), false);
}

/** Solves the 3 × 3 system `m · x = v` (Cramer's rule). */
function solve3(m, v) {
  const det = (a) =>
    a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
    a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
    a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]);
  const d = det(m);
  return [0, 1, 2].map((i) => det(m.map((row, r) => row.map((cell, c) => (c === i ? v[r] : cell)))) / d);
}

// ---------------------------------------------------------------- 1. read the tile

const { data, info } = await sharp(SRC).extract(TILE).removeAlpha().raw().toBuffer({ resolveWithObject: true });
const W = info.width;
const H = info.height;
const N = W * H;

/** Inside the tile's rounded outline, `inset` px away from its edge. */
function insideTile(x, y, inset) {
  const r = TILE_RADIUS - inset;
  const x0 = inset;
  const y0 = inset;
  const x1 = W - 1 - inset;
  const y1 = H - 1 - inset;
  if (x < x0 || x > x1 || y < y0 || y > y1) return false;
  const cx = x < x0 + r ? x0 + r : x > x1 - r ? x1 - r : x;
  const cy = y < y0 + r ? y0 + r : y > y1 - r ? y1 - r : y;
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

// ---------------------------------------------------------------- 2. the tile's wine gradient

// Wine has green ≈ 5–20, gold has green > 100 (dark shading down to ≈ 45).
const rough = new Uint8Array(N);
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const i = y * W + x;
    rough[i] = insideTile(x, y, 4) && data[i * 3 + 1] > 45 ? 1 : 0;
  }
}
const nearGold = morph(rough, W, H, 12);

/** Per channel `[c0, cx, cy]`: wine(x, y) = c0 + cx·x + cy·y in tile pixels. */
const plane = [0, 1, 2].map((c) => {
  let s1 = 0, sx = 0, sy = 0, sxx = 0, sxy = 0, syy = 0, sv = 0, sxv = 0, syv = 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (nearGold[i] || !insideTile(x, y, 8)) continue;
      const v = data[i * 3 + c];
      s1 += 1; sx += x; sy += y; sxx += x * x; sxy += x * y; syy += y * y;
      sv += v; sxv += x * v; syv += y * v;
    }
  }
  return solve3(
    [
      [s1, sx, sy],
      [sx, sxx, sxy],
      [sy, sxy, syy],
    ],
    [sv, sxv, syv],
  );
});
const wineAt = (c, x, y) => plane[c][0] + plane[c][1] * x + plane[c][2] * y;
const hex = (x, y) =>
  '#' + [0, 1, 2].map((c) => Math.round(wineAt(c, x, y)).toString(16).padStart(2, '0')).join('').toUpperCase();
console.log(
  `tile wine: top-left ${hex(0, 0)}  centre ${hex(W / 2, H / 2)}  bottom-right ${hex(W - 1, H - 1)}`,
);

// ---------------------------------------------------------------- 3. key the gold out

/**
 * The gold artwork on transparency, tile-sized: `{ rgba, bands }` where
 * `bands` are its rows top to bottom (rings, Wedbook, Matrimony) as
 * `[top, bottom]`.
 */
function keyGold() {
  // Clearly gold: well above the wine's green (JPEG bleeds a little gold into
  // the wine next to an edge, hence the margin).
  const ink = new Uint8Array(N);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      ink[i] = insideTile(x, y, 3) && data[i * 3 + 1] - wineAt(1, x, y) > 30 ? 1 : 0;
    }
  }
  const core = morph(ink, W, H, 1, true); // safely inside a stroke: opaque as it is
  const fringe = morph(ink, W, H, 2); // the stroke plus its anti-aliased edge

  // The gold right next to each edge pixel: the average of the nearby core
  // pixels; thin strokes without a core fall back to the nearby ink, then to
  // the artwork's mean gold.
  const localGold = (mask, radius) => {
    const weight = blur(mask, W, H, radius);
    return [0, 1, 2].map((c) => {
      const ch = new Float32Array(N);
      for (let i = 0; i < N; i++) ch[i] = mask[i] ? data[i * 3 + c] : 0;
      const sum = blur(ch, W, H, radius);
      for (let i = 0; i < N; i++) sum[i] = weight[i] > 0.02 ? sum[i] / weight[i] : -1;
      return sum;
    });
  };
  const nearCore = localGold(core, 1);
  const nearInk = localGold(ink, 3);
  const mean = [0, 0, 0];
  let count = 0;
  for (let i = 0; i < N; i++) {
    if (!core[i]) continue;
    for (let c = 0; c < 3; c++) mean[c] += data[i * 3 + c];
    count++;
  }
  for (let c = 0; c < 3; c++) mean[c] /= count;

  const rgba = Buffer.alloc(N * 4);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      if (!fringe[i]) continue;
      const p = [data[i * 3], data[i * 3 + 1], data[i * 3 + 2]];
      if (core[i]) {
        rgba[i * 4] = p[0];
        rgba[i * 4 + 1] = p[1];
        rgba[i * 4 + 2] = p[2];
        rgba[i * 4 + 3] = 255;
        continue;
      }
      const bg = [wineAt(0, x, y), wineAt(1, x, y), wineAt(2, x, y)];
      const gold = nearCore[0][i] >= 0 ? nearCore.map((ch) => ch[i]) : nearInk[0][i] >= 0 ? nearInk.map((ch) => ch[i]) : mean;
      // How far this pixel is from the wine towards the gold: its coverage.
      const d = [gold[0] - bg[0], gold[1] - bg[1], gold[2] - bg[2]];
      const t = ((p[0] - bg[0]) * d[0] + (p[1] - bg[1]) * d[1] + (p[2] - bg[2]) * d[2]) / (d[0] ** 2 + d[1] ** 2 + d[2] ** 2);
      let alpha = Math.min(1, Math.max(0, t));
      if (alpha < 0.06) continue;
      if (alpha > 0.94) alpha = 1;
      for (let c = 0; c < 3; c++) {
        // Un-mix: the colour that, laid over the wine at `alpha`, gives the
        // source pixel. Faint pixels would only amplify JPEG noise — they take
        // the neighbouring gold instead.
        const v = alpha >= 1 ? p[c] : alpha < 0.35 ? gold[c] : bg[c] + (p[c] - bg[c]) / alpha;
        rgba[i * 4 + c] = Math.round(Math.min(255, Math.max(0, v)));
      }
      rgba[i * 4 + 3] = Math.round(alpha * 255);
    }
  }

  const bands = [];
  let start = -1;
  for (let y = 0; y < H; y++) {
    let any = false;
    for (let x = 0; x < W && !any; x++) any = rgba[(y * W + x) * 4 + 3] > 40;
    if (any && start < 0) start = y;
    if (!any && start >= 0) {
      bands.push([start, y - 1]);
      start = -1;
    }
  }
  if (start >= 0) bands.push([start, H - 1]);
  return { rgba, bands };
}

/** The keyed gold between rows `top`..`bottom`, trimmed to its bounding box, as PNG. */
async function goldRows(key, top, bottom) {
  const band = await sharp(key.rgba, { raw: { width: W, height: H, channels: 4 } })
    .extract({ left: 0, top, width: W, height: bottom - top + 1 })
    .png()
    .toBuffer();
  return sharp(band).trim({ threshold: 1 }).png().toBuffer();
}

// ---------------------------------------------------------------- 4. the rebuilt tile

/**
 * Repeatable white noise in [-0.5, 0.5) for a pixel and channel (an integer
 * hash with a full avalanche, so there is no pattern and every run gives the
 * same files).
 */
function noise(x, y, c) {
  let h = (Math.imul(x, 0x9e3779b1) ^ Math.imul(y, 0x85ebca77) ^ Math.imul(c + 1, 0xc2b2ae3d)) | 0;
  h ^= h >>> 16;
  h = Math.imul(h, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296 - 0.5;
}

/** The tile's wine gradient stretched over a SIZE × SIZE square (opaque PNG). */
async function wineSquare() {
  const raw = Buffer.alloc(SIZE * SIZE * 3);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const sx = (x / (SIZE - 1)) * (W - 1);
      const sy = (y / (SIZE - 1)) * (H - 1);
      // Dithered: a touch of noise hides the banding of so gentle a gradient.
      for (let c = 0; c < 3; c++) {
        raw[(y * SIZE + x) * 3 + c] = Math.round(Math.min(255, Math.max(0, wineAt(c, sx, sy) + noise(x, y, c))));
      }
    }
  }
  return sharp(raw, { raw: { width: SIZE, height: SIZE, channels: 3 } }).png().toBuffer();
}

/** `square` cut to a rounded tile on transparency. */
async function rounded(square) {
  const mask = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}"><rect width="${SIZE}" height="${SIZE}" rx="${CORNER}" fill="#fff"/></svg>`,
  );
  return sharp(square)
    .ensureAlpha()
    .composite([{ input: await sharp(mask, { density: 72 }).resize(SIZE, SIZE).png().toBuffer(), blend: 'dest-in' }])
    .png()
    .toBuffer();
}

/** `art` scaled to `width` px and laid on `base` (SIZE × SIZE) with its centre at (`cx`, `cy`). */
async function place(base, art, width, cx = SIZE / 2, cy = SIZE / 2) {
  const scaled = await sharp(art).resize({ width: Math.round(width), kernel: 'lanczos3' }).png().toBuffer();
  const meta = await sharp(scaled).metadata();
  return sharp(base)
    .composite([{ input: scaled, left: Math.round(cx - meta.width / 2), top: Math.round(cy - meta.height / 2) }])
    .png()
    .toBuffer();
}

/**
 * The smallest circle around the opaque pixels of `png`: its centre as a
 * fraction of the image size and its radius relative to the image width.
 */
async function enclosingCircle(png) {
  const { data: px, info: m } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const points = [];
  for (let y = 0; y < m.height; y++) {
    let first = -1;
    let last = -1;
    for (let x = 0; x < m.width; x++) {
      if (px[(y * m.width + x) * 4 + 3] > 24) {
        if (first < 0) first = x;
        last = x;
      }
    }
    if (first >= 0) points.push([first, y], [last, y]);
  }
  const reach = (cx, cy) => points.reduce((max, [x, y]) => Math.max(max, Math.hypot(x - cx, y - cy)), 0);
  let cx = m.width / 2;
  let cy = m.height / 2;
  let best = reach(cx, cy);
  for (let step = m.width / 8; step > 0.25; step /= 2) {
    for (let moved = true; moved; ) {
      moved = false;
      for (const [dx, dy] of [[step, 0], [-step, 0], [0, step], [0, -step]]) {
        const r = reach(cx + dx, cy + dy);
        if (r < best - 1e-6) {
          best = r;
          cx += dx;
          cy += dy;
          moved = true;
        }
      }
    }
  }
  return { cx: cx / m.width, cy: cy / m.height, radius: best / m.width, aspect: m.height / m.width };
}

// ---------------------------------------------------------------- 5. render everything

const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

async function write(buf, size, file) {
  await mkdir(path.dirname(file), { recursive: true });
  await sharp(buf).resize(size, size, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toFile(file);
  console.log(`${path.relative(app, file)}  ${size}px`);
}

const key = keyGold();
if (key.bands.length !== 3) {
  throw new Error(`expected 3 bands of gold (rings, Wedbook, Matrimony), found ${key.bands.length}: ${JSON.stringify(key.bands)}`);
}
const [ringsRows, , matrimonyRows] = key.bands;
const rings = await goldRows(key, ...ringsRows);
const artwork = await goldRows(key, ringsRows[0], matrimonyRows[1]); // rings + both wordmark lines

const square = await wineSquare();
const tile = await rounded(square);

// The tile as supplied: the artwork at the source's size, centred.
const logoTile = await place(tile, artwork, SIZE * ART_WIDTH);
// The rings alone, for sizes where the wordmark can no longer be read.
const markTile = await place(tile, rings, SIZE * MARK_WIDTH);

// Adaptive icon. Background: the same wine, full bleed. Foreground: the whole
// artwork, scaled so its enclosing circle is the safe zone and centred on it.
const circle = await enclosingCircle(artwork);
const fgWidth = (SIZE * SAFE_RADIUS) / circle.radius;
const transparent = await sharp({ create: { width: SIZE, height: SIZE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
  .png()
  .toBuffer();
const foreground = await place(
  transparent,
  artwork,
  fgWidth,
  SIZE / 2 + (0.5 - circle.cx) * fgWidth,
  SIZE / 2 + (0.5 - circle.cy) * fgWidth * circle.aspect,
);
console.log(`adaptive foreground: artwork ${Math.round(fgWidth)} px wide on the ${SIZE} px layer`);

await mkdir(logoDir, { recursive: true });
await write(logoTile, 512, path.join(logoDir, 'logo.png'));
await write(logoTile, 1024, path.join(logoDir, 'logo_1024.png'));
await write(markTile, 256, path.join(logoDir, 'logo_mark.png'));

for (const [density, factor] of Object.entries(DENSITIES)) {
  const mip = path.join(res, `mipmap-${density}`);
  await write(logoTile, 48 * factor, path.join(mip, 'ic_launcher.png'));
  await write(square, 108 * factor, path.join(mip, 'ic_launcher_background.png'));
  await write(foreground, 108 * factor, path.join(mip, 'ic_launcher_foreground.png'));
  await write(logoTile, 128 * factor, path.join(res, `drawable-${density}`, 'launch_logo.png'));
}
console.log('done');
