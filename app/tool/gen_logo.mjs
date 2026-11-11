// Generates the Wedbook Agent logo and every Android icon size from the
// supplied brand artwork (SPEC §9.18 A).
//
//   cd app && node tool/gen_logo.mjs
//
// Source: assets/logo/wedbook_agent_source.jpg — a rounded royal-blue tile on a
// white canvas; on it two interlocked gold rings holding the ♂ and ♀ signs and
// the gold serif wordmark "Wedbook" / "Agent".
//
// What the script does
//   1. finds the tile on the canvas and fits a smooth colour model to its
//      blue (a gentle diagonal gradient) — the JPEG noise is left behind;
//   2. un-mixes the gold artwork from that blue: every pixel becomes
//      `alpha × foreground + (1 − alpha) × blue`, with alpha measured against
//      the nearby pure gold, so edges carry gold (not blue-grey) and the soft
//      shadows under the rings survive as translucent dark pixels;
//   3. redraws the tile as a clean SQUARE (the source tile is 537 × 560):
//      the fitted blue under a crisp rounded mask, the artwork exactly where
//      the source has it — no white fringe, no JPEG blocks in the blue.
//
// Outputs (same file names the app has always used)
//   assets/logo/logo.png                      512 px tile, used in-app (splash, About)
//   assets/logo/logo_1024.png                 1024 px tile (store listings, docs)
//   assets/logo/logo_mark.png                 the gold rings alone on transparency, 720 × 432
//   android/.../mipmap-*/ic_launcher.png      legacy launcher icon (the tile)
//   android/.../mipmap-*/ic_launcher_background.png   adaptive: full-bleed tile blue
//   android/.../mipmap-*/ic_launcher_foreground.png   adaptive: rings + wordmark in the safe zone
//   android/.../mipmap-*/ic_launcher_monochrome.png   adaptive: their silhouette
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
const SRC = path.join(logoDir, 'wedbook_agent_source.jpg');

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth = (lo, hi, v) => {
  const t = clamp01((v - lo) / (hi - lo));
  return t * t * (3 - 2 * t);
};

// ---------------------------------------------------------------- 1. the tile and its blue

const src = await sharp(SRC).removeAlpha().raw().toBuffer({ resolveWithObject: true });
const W = src.info.width;
const H = src.info.height;
const px = (x, y, c) => src.data[(y * W + x) * 3 + c];

/** Background blue has blue far above red; gold, highlights and the canvas do not. */
const isBlue = (x, y) => px(x, y, 2) - px(x, y, 0) > 40;

const tile = (() => {
  let x0 = W, x1 = -1, y0 = H, y1 = -1;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      if (!isBlue(x, y)) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (x1 < 0) throw new Error('No blue tile found in the source artwork');
  return { left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 };
})();
const tileCx = tile.left + tile.width / 2;
const tileCy = tile.top + tile.height / 2;
console.log(`tile  x ${tile.left}..${tile.left + tile.width - 1}  y ${tile.top}..${tile.top + tile.height - 1}  (${tile.width} × ${tile.height})`);

/** Inside the tile, away from its rim and its rounded corners. */
function inTileCore(x, y, inset) {
  const l = tile.left + inset, r = tile.left + tile.width - 1 - inset;
  const t = tile.top + inset, b = tile.top + tile.height - 1 - inset;
  if (x < l || x > r || y < t || y > b) return false;
  const corner = Math.round(tile.width * 0.24);
  const nearX = x < tile.left + corner || x > tile.left + tile.width - 1 - corner;
  const nearY = y < tile.top + corner || y > tile.top + tile.height - 1 - corner;
  return !(nearX && nearY);
}

// "Clean" blue = blue with no artwork within 7 px (keeps shadows and JPEG
// ringing out of the fit).
const cleanBlue = (() => {
  const R = 7;
  const art = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) art[y * W + x] = isBlue(x, y) ? 0 : 1;
  const tmp = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      let v = 0;
      for (let k = Math.max(0, x - R); k <= Math.min(W - 1, x + R) && !v; k++) v = art[y * W + k];
      tmp[y * W + x] = v;
    }
  }
  const out = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      let v = 0;
      for (let k = Math.max(0, y - R); k <= Math.min(H - 1, y + R) && !v; k++) v = tmp[k * W + x];
      out[y * W + x] = v ? 0 : 1;
    }
  }
  return out;
})();

/** Solves the 6×6 normal equations (Gaussian elimination with pivoting). */
function solve(A, b) {
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      const f = M[r][c] / M[c][c];
      for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k];
    }
  }
  return M.map((row, i) => row[n] / row[i]);
}

const basis = (u, v) => [1, u, v, u * u, u * v, v * v];
/** Source pixel → tile-relative coordinates (both in units of the tile height). */
const uOf = (x) => (x - tileCx) / tile.height;
const vOf = (y) => (y - tileCy) / tile.height;

/** Quadratic colour model of the tile's blue, fitted twice (outliers dropped). */
const model = (() => {
  let coef = null;
  for (let pass = 0; pass < 2; pass++) {
    const AtA = Array.from({ length: 6 }, () => new Array(6).fill(0));
    const Atb = [0, 1, 2].map(() => new Array(6).fill(0));
    let n = 0;
    for (let y = tile.top; y < tile.top + tile.height; y++) {
      for (let x = tile.left; x < tile.left + tile.width; x++) {
        if (!cleanBlue[y * W + x] || !inTileCore(x, y, 12)) continue;
        const f = basis(uOf(x), vOf(y));
        if (coef) {
          let off = 0;
          for (let c = 0; c < 3; c++) {
            let m = 0;
            for (let k = 0; k < 6; k++) m += coef[c][k] * f[k];
            off = Math.max(off, Math.abs(m - px(x, y, c)));
          }
          if (off > 10) continue;
        }
        for (let i = 0; i < 6; i++) {
          for (let j = 0; j < 6; j++) AtA[i][j] += f[i] * f[j];
          for (let c = 0; c < 3; c++) Atb[c][i] += f[i] * px(x, y, c);
        }
        n++;
      }
    }
    coef = [0, 1, 2].map((c) => solve(AtA, Atb[c]));
    console.log(`blue model pass ${pass + 1}: ${n} samples`);
  }
  return coef;
})();

/** The tile's blue at tile-relative (u, v), as [r, g, b] floats. */
function blueAt(u, v, out) {
  const f0 = u, f1 = v, f2 = u * u, f3 = u * v, f4 = v * v;
  for (let c = 0; c < 3; c++) {
    const k = model[c];
    out[c] = k[0] + k[1] * f0 + k[2] * f1 + k[3] * f2 + k[4] * f3 + k[5] * f4;
  }
  return out;
}
const hex = (rgb) => '#' + rgb.map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('').toUpperCase();
{
  const t = [0, 0, 0];
  const a = tile.width / tile.height / 2;
  console.log(
    `tile blue  centre ${hex(blueAt(0, 0, t))}  top-left ${hex(blueAt(-a, -0.5, t))}  bottom-right ${hex(blueAt(a, 0.5, t))}`,
  );
}

// ---------------------------------------------------------------- 2. un-mix the gold artwork

/** Bounding box of everything that is not blue, well inside the tile. */
const artBox = (() => {
  let x0 = W, x1 = -1, y0 = H, y1 = -1;
  for (let y = tile.top; y < tile.top + tile.height; y++) {
    for (let x = tile.left; x < tile.left + tile.width; x++) {
      if (!inTileCore(x, y, 10)) continue;
      if (px(x, y, 0) - px(x, y, 2) < 40) continue; // gold: red far above blue
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  return { x0, x1, y0, y1 };
})();
console.log(`gold  x ${artBox.x0}..${artBox.x1}  y ${artBox.y0}..${artBox.y1}`);

// The window we work in: the artwork plus room for its shadows, kept clear
// of the tile's rim.
const PAD = 14;
const win = (() => {
  const left = Math.max(tile.left + 8, artBox.x0 - PAD);
  const top = Math.max(tile.top + 8, artBox.y0 - PAD);
  const right = Math.min(tile.left + tile.width - 9, artBox.x1 + PAD);
  const bottom = Math.min(tile.top + tile.height - 9, artBox.y1 + PAD);
  return { left, top, width: right - left + 1, height: bottom - top + 1 };
})();

// Work at 3× so the keyed edges come out crisp when scaled back down.
const K = 3;
const ww = win.width * K;
const wh = win.height * K;
const up = await sharp(SRC)
  .removeAlpha()
  .extract(win)
  .resize(ww, wh, { kernel: 'mitchell' })
  .raw()
  .toBuffer();

/** Separable box blur, `passes` times (≈ gaussian). Returns a new Float32Array. */
function blur(input, w, h, r, passes = 2) {
  let a = Float32Array.from(input);
  let b = new Float32Array(w * h);
  const win2 = 2 * r + 1;
  for (let p = 0; p < passes; p++) {
    for (let y = 0; y < h; y++) {
      let sum = 0;
      const row = y * w;
      for (let x = -r; x <= r; x++) sum += a[row + Math.min(w - 1, Math.max(0, x))];
      for (let x = 0; x < w; x++) {
        b[row + x] = sum / win2;
        sum += a[row + Math.min(w - 1, x + r + 1)] - a[row + Math.max(0, x - r)];
      }
    }
    for (let x = 0; x < w; x++) {
      let sum = 0;
      for (let y = -r; y <= r; y++) sum += b[Math.min(h - 1, Math.max(0, y)) * w + x];
      for (let y = 0; y < h; y++) {
        a[y * w + x] = sum / win2;
        sum += b[Math.min(h - 1, y + r + 1) * w + x] - b[Math.max(0, y - r) * w + x];
      }
    }
  }
  return a;
}

/** Corner radius of the tile as a fraction of its width (measured: ≈ 108 / 537). */
const CORNER = 0.2;

/**
 * 1 well inside the tile's rounded shape, 0 at `inset` px from its edge and
 * beyond — keeps the white canvas behind the corners out of the artwork.
 */
function insideTile(sx, sy, inset) {
  const radius = tile.width * CORNER;
  const qx = Math.abs(sx - (tileCx - 0.5)) - (tile.width / 2 - radius);
  const qy = Math.abs(sy - (tileCy - 0.5)) - (tile.height / 2 - radius);
  const d = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - radius;
  return smooth(0, 3, -d - inset);
}

const N = ww * wh;
const bg = new Float32Array(N * 3); // the blue under every pixel
const dist = new Float32Array(N); // colour distance from that blue (0 outside the tile)
{
  const t = [0, 0, 0];
  for (let y = 0; y < wh; y++) {
    const sy = win.top + (y + 0.5) / K - 0.5;
    const v = vOf(sy);
    for (let x = 0; x < ww; x++) {
      const i = y * ww + x;
      const sx = win.left + (x + 0.5) / K - 0.5;
      blueAt(uOf(sx), v, t);
      let d2 = 0;
      for (let c = 0; c < 3; c++) {
        bg[i * 3 + c] = t[c];
        const d = up[i * 3 + c] - t[c];
        d2 += d * d;
      }
      dist[i] = Math.sqrt(d2) * insideTile(sx, sy, 7);
    }
  }
}

// `pure` ≈ 1 where a pixel is clearly artwork. Its blurred colour is the
// "nearby gold" an edge pixel is measured against.
const pure = new Float32Array(N);
const solid = new Float32Array(N);
for (let i = 0; i < N; i++) {
  pure[i] = smooth(50, 110, dist[i]);
  solid[i] = dist[i] > 60 ? 1 : 0;
}
const nearW = blur(pure, ww, wh, Math.round(K * 1.3));
const nearC = [0, 1, 2].map((c) => {
  const weighted = new Float32Array(N);
  for (let i = 0; i < N; i++) weighted[i] = pure[i] * up[i * 3 + c];
  return blur(weighted, ww, wh, Math.round(K * 1.3));
});
// Fully inside a shape (≥ ~1 source px from its edge) → opaque, whatever the shading.
const inside = blur(solid, ww, wh, K);
// Anything far from the artwork is JPEG speckle, not shadow.
const reach = blur(pure, ww, wh, K * 4);

// Fallback foreground for strokes too thin to have a "pure" core: the mean gold.
const meanGold = (() => {
  const s = [0, 0, 0];
  let n = 0;
  for (let i = 0; i < N; i++) {
    if (dist[i] < 150 || up[i * 3] - up[i * 3 + 2] < 60) continue;
    for (let c = 0; c < 3; c++) s[c] += up[i * 3 + c];
    n++;
  }
  return s.map((v) => v / Math.max(1, n));
})();
console.log(`mean gold ${hex(meanGold)}`);

const TOL = 8; // JPEG noise we do not chase
const art = Buffer.alloc(N * 4); // the artwork, un-mixed: RGBA
const mono = Buffer.alloc(N * 4); // its silhouette: black + alpha
for (let i = 0; i < N; i++) {
  const p = [up[i * 3], up[i * 3 + 1], up[i * 3 + 2]];
  const b = [bg[i * 3], bg[i * 3 + 1], bg[i * 3 + 2]];
  const f = nearW[i] > 0.02 ? [nearC[0][i] / nearW[i], nearC[1][i] / nearW[i], nearC[2][i] / nearW[i]] : meanGold;

  // How far along the line blue → nearby gold this pixel sits.
  let dot = 0, len = 0;
  for (let c = 0; c < 3; c++) {
    dot += (p[c] - b[c]) * (f[c] - b[c]);
    len += (f[c] - b[c]) * (f[c] - b[c]);
  }
  const along = len > 1 ? clamp01(dot / len) : 0;
  // The least alpha that can explain the pixel at all (shadows are darker
  // than both the blue and the gold).
  let least = 0;
  for (let c = 0; c < 3; c++) {
    const d = p[c] - b[c];
    const room = d > 0 ? 255 - b[c] : Math.max(1, b[c]);
    least = Math.max(least, (Math.abs(d) - TOL) / room);
  }
  const raw = Math.max(along, clamp01(least), smooth(0.8, 0.98, inside[i]));
  if (raw <= 0.004) continue;
  const alpha = raw * smooth(10, 26, dist[i]) * smooth(0.004, 0.03, reach[i]);
  if (alpha <= 0.002) continue;

  for (let c = 0; c < 3; c++) {
    const v = b[c] + (p[c] - b[c]) / raw; // exact un-mix: composites back to the source
    art[i * 4 + c] = Math.round(Math.max(0, Math.min(255, v)));
  }
  art[i * 4 + 3] = Math.round(alpha * 255);
  // Silhouette: the gold itself, without the soft shadows around it.
  mono[i * 4 + 3] = Math.round(smooth(0.45, 0.85, Math.max(along, smooth(0.8, 0.98, inside[i])) * smooth(40, 90, dist[i])) * 255);
}

// ---------------------------------------------------------------- 3. geometry of the artwork

/** Opaque-ish artwork pixels per working row / the row runs they form. */
const strong = (i) => mono[i * 4 + 3] > 128;
const rowRuns = (() => {
  const runs = [];
  let start = -1;
  for (let y = 0; y <= wh; y++) {
    let on = false;
    if (y < wh) for (let x = 0; x < ww && !on; x++) on = strong(y * ww + x);
    if (on && start < 0) start = y;
    if (!on && start >= 0) {
      // Ignore one-row gaps (the dot of nothing between a descender and its line).
      if (runs.length && start - runs[runs.length - 1][1] <= 2 * K) runs[runs.length - 1][1] = y - 1;
      else runs.push([start, y - 1]);
      start = -1;
    }
  }
  return runs;
})();
if (rowRuns.length < 2) throw new Error('Expected the rings and the wordmark as separate rows of artwork');

/** Bounding box (working px) of the strong artwork between two rows. */
function boundsOf(yFrom, yTo) {
  let x0 = ww, x1 = -1, y0 = wh, y1 = -1;
  for (let y = yFrom; y <= yTo; y++) {
    for (let x = 0; x < ww; x++) {
      if (!strong(y * ww + x)) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  return { x0, x1, y0, y1 };
}
const ringsBox = boundsOf(rowRuns[0][0], rowRuns[0][1]);
// The rings end where the gap to the wordmark begins.
const ringsCut = Math.round((rowRuns[0][1] + rowRuns[1][0]) / 2);

/** Smallest circle around all strong artwork (Bădoiu–Clarkson), in working px. */
const circle = (() => {
  const pts = [];
  for (let y = 0; y < wh; y++) {
    let first = -1, last = -1;
    for (let x = 0; x < ww; x++) {
      if (!strong(y * ww + x)) continue;
      if (first < 0) first = x;
      last = x;
    }
    if (first >= 0) pts.push([first, y], [last, y]);
  }
  let cx = 0, cy = 0;
  for (const [x, y] of pts) {
    cx += x;
    cy += y;
  }
  cx /= pts.length;
  cy /= pts.length;
  let r = 0;
  for (let it = 1; it <= 4000; it++) {
    let far = pts[0], best = -1;
    for (const p of pts) {
      const d = (p[0] - cx) ** 2 + (p[1] - cy) ** 2;
      if (d > best) {
        best = d;
        far = p;
      }
    }
    r = Math.sqrt(best);
    cx += (far[0] - cx) / (it + 1);
    cy += (far[1] - cy) / (it + 1);
  }
  for (const p of pts) r = Math.max(r, Math.hypot(p[0] - cx, p[1] - cy));
  return { cx, cy, r };
})();

// ---------------------------------------------------------------- 4. render

const SIZE = 1024;

const raw4 = (buf) => sharp(buf, { raw: { width: ww, height: wh, channels: 4 } });

/**
 * The artwork (or its silhouette) drawn on a transparent `cw × ch` canvas:
 * `scale` output px per source px, with working-pixel (ax, ay) landing on
 * canvas (cx, cy). `rows` limits it to the first rows (the rings alone).
 */
async function drawArt(layer, { cw, ch, scale, ax, ay, cx, cy, rows = wh }) {
  const f = scale / K; // output px per working px
  const w = Math.max(1, Math.round(ww * f));
  const h = Math.max(1, Math.round(rows * f));
  const piece = await raw4(layer)
    .extract({ left: 0, top: 0, width: ww, height: rows })
    .resize(w, h, { kernel: 'lanczos3', fit: 'fill' })
    .png()
    .toBuffer();
  return sharp({ create: { width: cw, height: ch, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: piece, left: Math.round(cx - ax * f), top: Math.round(cy - ay * f) }])
    .png()
    .toBuffer();
}

/**
 * The tile's blue, full bleed, on a SIZE × SIZE canvas. `scale` = canvas px
 * per source px; the tile's centre sits on the canvas centre.
 */
function drawBlue(scale) {
  const out = Buffer.alloc(SIZE * SIZE * 3);
  const t = [0, 0, 0];
  for (let y = 0; y < SIZE; y++) {
    const v = (y + 0.5 - SIZE / 2) / scale / tile.height;
    for (let x = 0; x < SIZE; x++) {
      blueAt((x + 0.5 - SIZE / 2) / scale / tile.height, v, t);
      const i = (y * SIZE + x) * 3;
      for (let c = 0; c < 3; c++) out[i + c] = Math.round(Math.max(0, Math.min(255, t[c])));
    }
  }
  return sharp(out, { raw: { width: SIZE, height: SIZE, channels: 3 } }).png().toBuffer();
}

// --- the tile: the source layout, its height mapped onto the square.
const tileScale = SIZE / tile.height;
const tileBlue = await drawBlue(tileScale);
const tileArt = await drawArt(art, {
  cw: SIZE,
  ch: SIZE,
  scale: tileScale,
  ax: 0,
  ay: 0,
  // The window's top-left corner, measured from the tile's centre.
  cx: SIZE / 2 + (win.left - tileCx) * tileScale,
  cy: SIZE / 2 + (win.top - tileCy) * tileScale,
});
const roundedMask = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}">` +
    `<rect width="${SIZE}" height="${SIZE}" rx="${SIZE * CORNER}" ry="${SIZE * CORNER}" fill="#fff"/></svg>`,
);
const full = await sharp(tileBlue)
  .ensureAlpha()
  .composite([
    { input: tileArt, left: 0, top: 0 },
    { input: roundedMask, left: 0, top: 0, blend: 'dest-in' },
  ])
  .png()
  .toBuffer();

// --- adaptive icon: full-bleed blue behind, the artwork inside the 66/108
// safe circle (drawn to 62/108 so nothing touches the mask).
const background = tileBlue;
const SAFE = (62 / 108) * SIZE;
const fgScale = (SAFE / 2 / circle.r) * K; // output px per source px
const fgPlace = { cw: SIZE, ch: SIZE, scale: fgScale, ax: circle.cx, ay: circle.cy, cx: SIZE / 2, cy: SIZE / 2 };
const foreground = await drawArt(art, fgPlace);
const monochrome = await drawArt(mono, fgPlace);

// --- the mark: the rings alone, 5:3, filling 92% of the width.
const MARK_W = 720;
const MARK_H = 432;
const ringsW = (ringsBox.x1 - ringsBox.x0 + 1) / K; // source px
const mark = await drawArt(art, {
  cw: MARK_W,
  ch: MARK_H,
  scale: (MARK_W * 0.92) / ringsW,
  ax: (ringsBox.x0 + ringsBox.x1 + 1) / 2,
  ay: (ringsBox.y0 + ringsBox.y1 + 1) / 2,
  cx: MARK_W / 2,
  cy: MARK_H / 2,
  rows: ringsCut,
});

// ---------------------------------------------------------------- 5. write everything

const DENSITIES = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

async function write(buf, size, file, height = size) {
  await mkdir(path.dirname(file), { recursive: true });
  await sharp(buf).resize(size, height, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toFile(file);
  console.log(`${path.relative(app, file)}  ${size}${height === size ? '' : ` × ${height}`}px`);
}

await mkdir(logoDir, { recursive: true });
await write(full, 512, path.join(logoDir, 'logo.png'));
await write(mark, MARK_W, path.join(logoDir, 'logo_mark.png'), MARK_H);
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
