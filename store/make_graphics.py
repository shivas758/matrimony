"""Play Store graphics for both Wedbook apps (SPEC §9.20 G).

    python store/make_graphics.py            # icons + feature graphics
    python store/make_graphics.py --frames   # also frame the raw screenshots in store/<app>/raw/

Writes into store/<app>/:
  icon-512.png                  512×512, full-bleed (Play rounds the corners itself)
  feature-graphic-1024x500.png  the listing banner
  screenshots/NN_*.png          1080×1920 framed screenshots with a caption (from raw/)
Needs Pillow. Fonts come from backend/src/assets/fonts.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / 'backend' / 'src' / 'assets' / 'fonts'
SERIF = str(FONTS / 'PlayfairDisplay.ttf')
SANS = str(FONTS / 'Poppins-Regular.ttf')
SANS_SEMI = str(FONTS / 'Poppins-SemiBold.ttf')

APPS = {
    'wedbook-matrimony': {
        'logo': ROOT / 'customer_app' / 'assets' / 'logo' / 'logo_1024.png',
        'name': 'Wedbook Matrimony',
        'tagline': 'Find your life partner through trusted marriage bureaus',
        'points': 'Agent-approved profiles  ·  Privacy first  ·  Telugu & Kannada families',
        'dark': (58, 4, 25), 'mid': (84, 7, 41), 'light': (122, 18, 64),
        'captions': [
            'Sign in with just your mobile number',
            'Browse matching profiles from your community',
            'See full details once your agent approves',
            'Your profile, your ID — managed with your agent',
            'You choose what others can see',
            'Send interests and follow every reply',
        ],
    },
    'wedbook-agent': {
        'logo': ROOT / 'app' / 'assets' / 'logo' / 'logo_1024.png',
        'name': 'Wedbook Agent',
        'tagline': 'The workspace for marriage bureau agents',
        'points': 'Manage profiles  ·  Share securely  ·  Approve contacts',
        'dark': (2, 30, 74), 'mid': (4, 50, 112), 'light': (13, 74, 154),
        'captions': [
            'Secure login for registered agents',
            'All profiles from your communities',
            'Full details — contacts only on approval',
            'Add a profile in four simple steps',
            'Your clients, requests and interests in one place',
            'Share masked profiles in one tap',
        ],
    },
}
GOLD = (232, 194, 95)
WHITE = (255, 255, 255)


def gradient(size, c1, c2, horizontal=True):
    w, h = size
    img = Image.new('RGB', size, c1)
    draw = ImageDraw.Draw(img)
    steps = w if horizontal else h
    for i in range(steps):
        t = i / max(steps - 1, 1)
        col = tuple(round(c1[k] + (c2[k] - c1[k]) * t) for k in range(3))
        if horizontal:
            draw.line([(i, 0), (i, h)], fill=col)
        else:
            draw.line([(0, i), (w, i)], fill=col)
    return img


def edge_colour(logo):
    """The tile's own background colour, sampled just inside its top edge."""
    px = logo.convert('RGBA').getpixel((logo.width // 2, logo.height // 10))
    return px[:3]


def icon(app, cfg, out):
    logo = Image.open(cfg['logo']).convert('RGBA')
    # Trim the tile's rounded transparent corners (Play rounds the icon itself).
    m = round(logo.width * 0.055)
    logo = logo.crop((m, m, logo.width - m, logo.height - m))
    bg = Image.new('RGBA', logo.size, edge_colour(logo) + (255,))
    bg.alpha_composite(logo)
    bg.convert('RGB').resize((512, 512), Image.LANCZOS).save(out / 'icon-512.png', optimize=True)


def fitted(draw, text, path, size, width, minimum=14):
    """The largest font (≤ size) that fits `text` in `width`."""
    while size > minimum:
        font = ImageFont.truetype(path, size)
        if draw.textlength(text, font=font) <= width:
            return font
        size -= 1
    return ImageFont.truetype(path, minimum)


def wrap(draw, text, font, width):
    words, lines, cur = text.split(), [], ''
    for w in words:
        test = f'{cur} {w}'.strip()
        if draw.textlength(test, font=font) <= width:
            cur = test
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def feature(app, cfg, out):
    W, H = 1024, 500
    img = gradient((W, H), cfg['dark'], cfg['light']).convert('RGBA')
    # soft glow behind the logo
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((40, 60, 420, 440), fill=GOLD + (60,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    logo = Image.open(cfg['logo']).convert('RGBA').resize((300, 300), Image.LANCZOS)
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((86, 112, 386, 412), 60, fill=(0, 0, 0, 110))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    img.alpha_composite(logo, (80, 100))
    d = ImageDraw.Draw(img)
    x = 440
    room = W - x - 44
    title = fitted(d, cfg['name'], SERIF, 64, room)
    d.text((x, 120), cfg['name'], font=title, fill=GOLD)
    d.rounded_rectangle((x, 212, x + 70, 217), 3, fill=GOLD)
    tag = ImageFont.truetype(SANS_SEMI, 30)
    y = 238
    for line in wrap(d, cfg['tagline'], tag, W - x - 50):
        d.text((x, y), line, font=tag, fill=WHITE)
        y += 42
    pts = fitted(d, cfg['points'], SANS, 20, room)
    d.text((x, y + 18), cfg['points'], font=pts, fill=(255, 255, 255, 210))
    img.convert('RGB').save(out / 'feature-graphic-1024x500.png', optimize=True)


def frames(app, cfg, out):
    raw = sorted((out / 'raw').glob('*.png'))
    if not raw:
        print(f'  {app}: no raw screenshots yet')
        return
    dest = out / 'screenshots'
    dest.mkdir(exist_ok=True)
    W, H = 1080, 1920
    cap_font = ImageFont.truetype(SANS_SEMI, 58)
    for i, path in enumerate(raw):
        caption = cfg['captions'][i] if i < len(cfg['captions']) else ''
        img = gradient((W, H), cfg['mid'], cfg['dark'], horizontal=False).convert('RGBA')
        d = ImageDraw.Draw(img)
        y = 110
        # Balanced lines: the narrowest width that still needs no extra line.
        lines = wrap(d, caption, cap_font, W - 160)
        for width in range(W - 160, 400, -10):
            trial = wrap(d, caption, cap_font, width)
            if len(trial) > len(lines):
                break
            lines = trial
        for line in lines:
            tw = d.textlength(line, font=cap_font)
            d.text(((W - tw) / 2, y), line, font=cap_font, fill=WHITE)
            y += 76
        d.rounded_rectangle(((W - 90) / 2, y + 18, (W + 90) / 2, y + 24), 3, fill=GOLD)
        # the real screen, scaled into a rounded "phone" panel
        shot = Image.open(path).convert('RGB')
        top = y + 70
        ph = H - top - 70
        pw = round(ph * shot.width / shot.height)
        shot = shot.resize((pw, ph), Image.LANCZOS)
        x0 = (W - pw) // 2
        border = 14
        shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (x0 - border + 6, top - border + 16, x0 + pw + border + 6, top + ph + border + 16), 64, fill=(0, 0, 0, 120))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))
        ImageDraw.Draw(img).rounded_rectangle(
            (x0 - border, top - border, x0 + pw + border, top + ph + border), 64, fill=(16, 16, 20, 255))
        mask = Image.new('L', (pw, ph), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, pw, ph), 52, fill=255)
        img.paste(shot, (x0, top), mask)
        img.convert('RGB').save(dest / path.name, optimize=True)
    print(f'  {app}: {len(raw)} framed screenshots')


if __name__ == '__main__':
    for app, cfg in APPS.items():
        out = ROOT / 'store' / app
        out.mkdir(parents=True, exist_ok=True)
        icon(app, cfg, out)
        feature(app, cfg, out)
        print(f'  {app}: icon + feature graphic')
        if '--frames' in sys.argv:
            frames(app, cfg, out)
