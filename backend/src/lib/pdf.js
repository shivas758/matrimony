// Masked profile PDF for WhatsApp sharing (SPEC §4 Sharing, method 'pdf').
//
// Same exposure rules as the share card and the public page: everything here
// comes from lib/card.js publicRows(), so the three can never drift apart on
// what leaves the app. NEVER add an on-request field (SPEC §9.8: native place,
// birth place, work place, NRI place, parents, contact person, siblings,
// family details, property) or uploader identity here (CLAUDE.md rule 3,
// SPEC §3.3). Photos are the watermarked copies only.

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import PDFDocument from 'pdfkit';
import sharp from 'sharp';
import { ROW_GROUPS, formatDob, publicRows } from './card.js';
import { watermarkedBuffer } from './photos.js';

const FONTS = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'fonts');

// Brand palette — mirrors app/lib/ui/theme.dart.
const NAVY = '#0F2F52';
const NAVY_DEEP = '#081C33';
const GOLD = '#C9962E';
const GOLD_LIGHT = '#E8C25F';
const INK = '#1C2430';
const MUTED = '#6B7280';
const RULE = '#E7E2D8';
const IVORY = '#F7F5F0';

const PAGE_W = 595.28; // A4
const PAGE_H = 841.89;
const MARGIN = 36;
const HEADER_H = 84;
const FOOTER_H = 58;

/**
 * Renders the masked profile as a one-page (occasionally two-page) A4 PDF.
 * @param profile   output of profilePublic()
 * @param photoPaths stored file_paths, primary first (max 4 are used)
 */
export async function renderProfilePdf(profile, { agencyLabel, photoPaths = [] } = {}) {
  const label = agencyLabel || 'Mediator';
  const doc = new PDFDocument({
    size: 'A4',
    margin: 0,
    info: { Title: `${profile.full_name} — Profile`, Author: label, Creator: 'Mediator' },
  });
  const chunks = [];
  doc.on('data', (c) => chunks.push(c));
  const finished = new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });

  doc.registerFont('Body', path.join(FONTS, 'Poppins-Regular.ttf'));
  doc.registerFont('Semi', path.join(FONTS, 'Poppins-SemiBold.ttf'));
  doc.registerFont('Bold', path.join(FONTS, 'Poppins-Bold.ttf'));
  doc.registerFont('Display', path.join(FONTS, 'PlayfairDisplay.ttf'));

  const photos = await preparePhotos(photoPaths, label);

  drawHeader(doc, label);
  drawFooter(doc, label);

  // ---- left column: photos
  const colGap = 18;
  const leftW = 196;
  const leftX = MARGIN;
  const rightX = leftX + leftW + colGap;
  const rightW = PAGE_W - MARGIN - rightX;
  const top = HEADER_H + 26;

  let leftBottom = top;
  if (photos.length) {
    const mainH = 236;
    roundedImage(doc, photos[0], leftX, top, leftW, mainH, 12);
    leftBottom = top + mainH;
    const thumbs = photos.slice(1, 4);
    if (thumbs.length) {
      const gap = 8;
      const tw = (leftW - gap * (thumbs.length - 1)) / thumbs.length;
      const ty = leftBottom + gap;
      thumbs.forEach((buf, i) => roundedImage(doc, buf, leftX + i * (tw + gap), ty, tw, tw, 8));
      leftBottom = ty + tw;
    }
  } else {
    doc.save().roundedRect(leftX, top, leftW, 236, 12).fill(IVORY).restore();
    doc.font('Body').fontSize(11).fillColor(MUTED).text('No photo', leftX, top + 110, { width: leftW, align: 'center' });
    leftBottom = top + 236;
  }

  // ---- right column: name + facts
  let y = top - 4;
  doc.font('Display').fontSize(24).fillColor(NAVY).text(profile.full_name, rightX, y, { width: rightW });
  y = doc.y + 2;
  const sub = [
    profile.gender === 'bride' ? 'Bride' : 'Groom',
    profile.age ? `${profile.age} yrs${profile.dob ? ` (${formatDob(profile.dob)})` : ''}` : null,
    profile.community?.name,
  ]
    .filter(Boolean)
    .join('  ·  ');
  doc.font('Semi').fontSize(10.5).fillColor(GOLD).text(sub, rightX, y, { width: rightW });
  y = doc.y + 10;
  doc.save().moveTo(rightX, y).lineTo(rightX + 48, y).lineWidth(2).strokeColor(GOLD_LIGHT).stroke().restore();
  y += 14;

  const rows = publicRows(profile, { maxDetail: 110 });
  const bodyBottom = PAGE_H - FOOTER_H - 20;
  // Rows that do not fit beside the photo continue full-width underneath it.
  const groups = ROW_GROUPS.map(([title, labels]) => [title, rows.filter(([k]) => labels.includes(k))]).filter(
    ([, r]) => r.length,
  );

  let x = rightX;
  let w = rightW;
  const rowH = (k, v, width) => {
    doc.font('Body').fontSize(10);
    return Math.max(16, doc.heightOfString(v, { width: width - 108 })) + 7;
  };
  for (const [title, groupRows] of groups) {
    // Section title
    const need = 22 + rowH(groupRows[0][0], groupRows[0][1], w);
    ({ x, w, y } = flow(doc, { x, w, y, need, leftBottom, leftX, rightX, rightW, bodyBottom }));
    doc.font('Semi').fontSize(8.5).fillColor(GOLD).text(title.toUpperCase(), x, y, { width: w, characterSpacing: 1 });
    y = doc.y + 4;
    for (const [k, v] of groupRows) {
      const h = rowH(k, v, w);
      ({ x, w, y } = flow(doc, { x, w, y, need: h, leftBottom, leftX, rightX, rightW, bodyBottom }));
      doc.save().moveTo(x, y + h - 3).lineTo(x + w, y + h - 3).lineWidth(0.5).strokeColor(RULE).stroke().restore();
      doc.font('Body').fontSize(9).fillColor(MUTED).text(k, x, y + 2, { width: 100 });
      doc.font('Body').fontSize(10).fillColor(INK).text(v, x + 108, y + 1, { width: w - 108 });
      y += h;
    }
    y += 8;
  }

  // ---- about: full width below both columns
  if (profile.about) {
    y = Math.max(y, leftBottom + 18);
    const aboutTop = y + 6;
    if (aboutTop + 60 > bodyBottom) {
      newPage(doc, label);
      y = HEADER_H + 26;
    } else {
      y = aboutTop;
    }
    const fullW = PAGE_W - MARGIN * 2;
    doc.font('Semi').fontSize(8.5).fillColor(GOLD).text('ABOUT', MARGIN, y, { width: fullW, characterSpacing: 1 });
    y = doc.y + 4;
    doc.font('Body').fontSize(10).fillColor(INK).text(profile.about, MARGIN, y, {
      width: fullW,
      lineGap: 2.5,
      height: bodyBottom - y,
      ellipsis: true,
    });
  }

  doc.end();
  return finished;
}

/**
 * Decides where the next block goes: beside the photo, full-width below it,
 * or on a fresh page. Returns the (possibly new) x/w/y.
 */
function flow(doc, { x, w, y, need, leftBottom, leftX, rightX, rightW, bodyBottom }) {
  if (y + need <= bodyBottom) return { x, w, y };
  // Past the footer: if we were still in the right column, drop below the
  // photo column at full width first; otherwise start a new page.
  if (x === rightX && leftBottom + 18 + need <= bodyBottom && leftBottom + 18 > y - need) {
    return { x: leftX, w: PAGE_W - MARGIN * 2, y: leftBottom + 18 };
  }
  newPage(doc, doc.info.Author);
  return { x: leftX, w: PAGE_W - MARGIN * 2, y: HEADER_H + 26 };
}

function newPage(doc, label) {
  doc.addPage({ size: 'A4', margin: 0 });
  drawHeader(doc, label);
  drawFooter(doc, label);
}

function drawHeader(doc, label) {
  doc.save();
  doc.rect(0, 0, PAGE_W, HEADER_H).fill(NAVY);
  doc.rect(0, HEADER_H - 3, PAGE_W, 3).fill(GOLD);
  doc.font('Display').fontSize(22).fillColor(GOLD_LIGHT).text('Mediator', MARGIN, 24);
  doc.font('Body').fontSize(7.5).fillColor('#FFFFFF').opacity(0.75)
    .text('MATRIMONY PARTNERS', MARGIN, 52, { characterSpacing: 2 });
  doc.opacity(1);
  doc.font('Semi').fontSize(10).fillColor('#FFFFFF').text(label, PAGE_W / 2, 30, {
    width: PAGE_W / 2 - MARGIN,
    align: 'right',
  });
  doc.font('Body').fontSize(8).fillColor('#FFFFFF').opacity(0.7)
    .text('Profile shared privately', PAGE_W / 2, 46, { width: PAGE_W / 2 - MARGIN, align: 'right' });
  doc.restore();
}

function drawFooter(doc, label) {
  doc.save();
  const y = PAGE_H - FOOTER_H;
  doc.rect(0, y, PAGE_W, FOOTER_H).fill(IVORY);
  doc.rect(0, y, PAGE_W, 1).fill(RULE);
  doc.font('Semi').fontSize(10).fillColor(NAVY_DEEP).text(label, MARGIN, y + 16, {
    width: PAGE_W - MARGIN * 2,
    align: 'center',
  });
  doc.font('Body').fontSize(8.5).fillColor(MUTED).text('Contact your agent for details', MARGIN, y + 32, {
    width: PAGE_W - MARGIN * 2,
    align: 'center',
  });
  doc.restore();
}

function roundedImage(doc, buf, x, y, w, h, r) {
  doc.save();
  doc.roundedRect(x, y, w, h, r).clip();
  doc.image(buf, x, y, { cover: [w, h], align: 'center', valign: 'center' });
  doc.restore();
}

/** Watermarked, downsized JPEGs; an unreadable file is skipped rather than fatal. */
async function preparePhotos(paths, label) {
  const out = [];
  for (const [i, relPath] of paths.slice(0, 4).entries()) {
    try {
      const wm = await watermarkedBuffer(relPath, label);
      out.push(
        await sharp(wm)
          .resize({ width: i === 0 ? 720 : 300, withoutEnlargement: true })
          .jpeg({ quality: i === 0 ? 82 : 76 })
          .toBuffer(),
      );
    } catch {
      // skip
    }
  }
  return out;
}
