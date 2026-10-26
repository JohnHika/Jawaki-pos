"""Generates the Axon POS launcher icon set (default + living variants).

Run from the repo root:  python mobile/tool/icons/generate_icons.py

Writes, for every variant:
  res/mipmap-xxxhdpi/ic_launcher<suffix>_foreground.png  (432px adaptive layer)
  res/mipmap-xxxhdpi/ic_launcher<suffix>_background.png  (432px adaptive layer)
  res/mipmap-<density>/ic_launcher<suffix>.png            (legacy, pre-Android 8)
  res/mipmap-anydpi-v26/ic_launcher<suffix>.xml           (adaptive descriptor)
and a preview sheet next to this script. The default variant also refreshes
assets/images/axon_app_icon_{512,1024}.png and a monochrome layer for the
Android 13 themed icon.

Art lives inside the 66dp adaptive safe zone, so every launcher mask (circle,
squircle, rounded square) keeps the whole mark.
"""
import math
import os
import sys
import colorsys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
RES = os.path.join(ROOT, 'mobile', 'android', 'app', 'src', 'main', 'res')
ASSETS = os.path.join(ROOT, 'mobile', 'assets', 'images')

LAYER = 432          # 108dp @ xxxhdpi
SS = 4               # supersampling factor

WHITE = (255, 255, 255, 255)
ORANGE = (255, 122, 51, 255)   # DesignColors.brand
DEEP = (232, 70, 24, 255)

def hsl(hue, saturation=0.82, lightness=0.58):
    rgb = colorsys.hls_to_rgb((hue % 360) / 360, lightness, saturation)
    return tuple(round(channel * 255) for channel in rgb)


def tiered_variant(kind, level, hue, saturation=0.68):
    """Make a distinct, cohesive gradient for a numbered shop-state look."""
    top_lightness = 0.63 - (level % 3) * 0.025
    bottom_lightness = 0.37 + (level % 3) * 0.025
    return (
        hsl(hue, saturation, top_lightness),
        hsl(hue + 8, saturation, bottom_lightness),
        kind,
        level,
    )


# Each entry is (background start, background end, state, threshold). There
# are 24 real, state-selected looks: 8 streak, 8 stock-alert, 7 record-day,
# and the everyday icon. The Axon cube remains unchanged in every look.
VARIANTS = {
    # suffix: (bg top-left, bg bottom-right, kind, level)
    '':        ((255, 160, 90), (255, 90, 30), 'standard', 0),
    '_streak': ((255, 128, 64), (214, 40, 28), 'streak', 3),
    '_alert':  ((255, 160, 90), (255, 90, 30), 'alert', 1),
    '_gold':   ((255, 218, 96), (255, 150, 28), 'record', 0),
}

for level, hue in zip(range(6, 13), (4, 12, 20, 28, 346, 354, 0)):
    VARIANTS[f'_streak_{level}'] = tiered_variant('streak', level, hue)

for level, hue in zip(range(3, 10), (350, 358, 6, 14, 342, 348, 2)):
    VARIANTS[f'_alert_{level}'] = tiered_variant('alert', level, hue)

for level, hue in zip((5, 10, 20, 50, 100, 200), (42, 36, 48, 30, 24, 44)):
    VARIANTS[f'_gold_{level}'] = tiered_variant(
        'record', level, hue, saturation=0.72)


def lerp(a, b, t):
    return a + (b - a) * t


def gradient(size, c1, c2):
    """Diagonal gradient, top-left c1 to bottom-right c2."""
    data = bytearray()
    denom = 2.0 * (size - 1)
    for y in range(size):
        row = bytearray(size * 4)
        for x in range(size):
            t = (x + y) / denom
            i = x * 4
            row[i] = int(lerp(c1[0], c2[0], t))
            row[i + 1] = int(lerp(c1[1], c2[1], t))
            row[i + 2] = int(lerp(c1[2], c2[2], t))
            row[i + 3] = 255
        data.extend(row)
    return Image.frombytes('RGBA', (size, size), bytes(data))


def rounded_poly(draw, pts, fill, r):
    """Polygon with softly rounded corners (fill + curved-join outline)."""
    draw.polygon(pts, fill=fill)
    draw.line(pts + [pts[0]], fill=fill, width=int(r), joint='curve')
    for x, y in pts:
        draw.ellipse([x - r / 2, y - r / 2, x + r / 2, y + r / 2], fill=fill)


def shrink(pts, amount):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    out = []
    for x, y in pts:
        d = math.hypot(x - cx, y - cy) or 1
        k = max(0, d - amount) / d
        out.append((cx + (x - cx) * k, cy + (y - cy) * k))
    return out


def cube_points(cx, cy, R):
    c30 = math.cos(math.radians(30))
    T = (cx, cy - R)
    UR = (cx + R * c30, cy - R / 2)
    LR = (cx + R * c30, cy + R / 2)
    B = (cx, cy + R)
    LL = (cx - R * c30, cy + R / 2)
    UL = (cx - R * c30, cy - R / 2)
    C = (cx, cy)
    return T, UR, LR, B, LL, UL, C


def face_map(origin, a, b):
    ox, oy = origin
    return lambda u, v: (ox + u * (a[0] - ox) + v * (b[0] - ox),
                         oy + u * (a[1] - oy) + v * (b[1] - oy))


def draw_cube(d, cx, cy, R, faces, mark, S, nodes=True):
    """The Axon cube: three faces, a barcode on the left, a check on the right."""
    T, UR, LR, B, LL, UL, C = cube_points(cx, cy, R)
    gap = 5 * S
    corner = 14 * S
    top = shrink([T, UR, C, UL], gap)
    left = shrink([UL, C, B, LL], gap)
    right = shrink([C, UR, LR, B], gap)
    rounded_poly(d, top, faces[0], corner)
    rounded_poly(d, left, faces[1], corner)
    rounded_poly(d, right, faces[2], corner)

    # Axon nodes: the original mark's glowing vertices
    for (nx, ny, nr) in (((T[0], T[1], 15), (UR[0], UR[1], 11)) if nodes else ()):
        d.ellipse([nx - nr * S, ny - nr * S, nx + nr * S, ny + nr * S], fill=WHITE)
        d.ellipse([nx - nr * 0.5 * S, ny - nr * 0.5 * S, nx + nr * 0.5 * S, ny + nr * 0.5 * S], fill=mark)

    # barcode on the left face (retail / point-of-sale cue)
    P = face_map(UL, C, LL)
    bars = [(0.18, 0.045), (0.27, 0.095), (0.41, 0.045), (0.50, 0.075), (0.62, 0.045), (0.71, 0.09)]
    for u, w in bars:
        quad = [P(u, 0.24), P(u + w, 0.24), P(u + w, 0.76), P(u, 0.76)]
        d.polygon(quad, fill=mark)

    # "paid" check on the right face
    Q = face_map(C, UR, B)
    check = [Q(0.22, 0.50), Q(0.42, 0.68), Q(0.80, 0.26)]
    d.line(check, fill=mark, width=int(13 * S), joint='curve')
    for x, y in (check[0], check[-1]):
        d.ellipse([x - 6.5 * S, y - 6.5 * S, x + 6.5 * S, y + 6.5 * S], fill=mark)


def flame(d, cx, cy, h, S):
    w = h * 0.78
    pts = []
    n = 40
    # teardrop with a flicked tip
    for i in range(n + 1):
        t = i / n
        a = lerp(math.pi * 0.05, math.pi * 0.95, t)
        x = cx + math.cos(a) * w * 0.5 * (1 if t < 0.5 else 1)
        y = cy + h * 0.12 + math.sin(a) * h * 0.38
        pts.append((x, y))
    tip = [(cx + w * 0.50, cy + h * 0.12), (cx + w * 0.32, cy - h * 0.18),
           (cx + w * 0.10, cy - h * 0.50), (cx - w * 0.04, cy - h * 0.18),
           (cx - w * 0.20, cy - h * 0.34), (cx - w * 0.50, cy + h * 0.12)]
    d.polygon(tip + list(reversed(pts[::-1])), fill=(255, 120, 30, 255))
    d.polygon(tip, fill=(255, 120, 30, 255))
    d.ellipse([cx - w * 0.5, cy - h * 0.26, cx + w * 0.5, cy + h * 0.50], fill=(255, 120, 30, 255))
    d.ellipse([cx - w * 0.26, cy + h * 0.02, cx + w * 0.26, cy + h * 0.46], fill=(255, 205, 60, 255))


def sparkle(d, cx, cy, r, color):
    pts = []
    for i in range(8):
        a = i * math.pi / 4
        rad = r if i % 2 == 0 else r * 0.28
        pts.append((cx + math.cos(a) * rad, cy + math.sin(a) * rad))
    d.polygon(pts, fill=color)


def badge(d, cx, cy, r, S, fill=WHITE):
    ring = 4 * S
    d.ellipse([cx - r - ring, cy - r - ring, cx + r + ring, cy + r + ring], fill=(0, 0, 0, 40))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def foreground(suffix, mono=False):
    S = SS
    size = LAYER * S
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    kind = VARIANTS[suffix][2]
    shift = 0 if kind in ('standard', 'record') else -12
    cx = size / 2 + shift * S
    cy = size / 2 + shift * S
    R = 98 * S

    if mono:
        # Themed icons are tinted by the system from alpha alone: a solid cube
        # silhouette with the barcode, check and nodes cut out.
        black = (0, 0, 0, 255)
        clear = (0, 0, 0, 0)
        draw_cube(d, cx, cy, R, (black, black, black), clear, S, nodes=False)
        marks = Image.new('RGBA', (size, size), clear)
        draw_cube(ImageDraw.Draw(marks), cx, cy, R, (clear, clear, clear), WHITE, S, nodes=False)
        img.putalpha(ImageChops.subtract(img.getchannel('A'), marks.getchannel('A')))
        return img.resize((LAYER, LAYER), Image.LANCZOS)

    faces = (WHITE, (255, 233, 218, 255), (255, 208, 176, 255))
    mark = ORANGE
    if kind == 'record':
        faces = (WHITE, (255, 243, 214, 255), (255, 226, 160, 255))
        mark = (232, 120, 10, 255)
    elif kind == 'streak':
        mark = DEEP
    elif kind == 'alert':
        mark = (190, 42, 48, 255)

    # soft drop shadow so the cube lifts off the tile
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    draw_cube(sd, cx, cy + 8 * S, R, ((0, 0, 0, 70),) * 3, (0, 0, 0, 0), S)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10 * S))
    img = Image.alpha_composite(img, shadow)
    d = ImageDraw.Draw(img)
    draw_cube(d, cx, cy, R, faces, mark, S)

    bx, by, br = size / 2 + 82 * S, size / 2 + 82 * S, 40 * S
    if kind == 'streak':
        badge(d, bx, by, br, S)
        flame(d, bx, by - 2 * S, 56 * S, S)
    elif kind == 'alert':
        badge(d, bx, by, br, S, fill=(229, 57, 53, 255))
        d.rounded_rectangle([bx - 5 * S, by - 24 * S, bx + 5 * S, by + 6 * S], radius=5 * S, fill=WHITE)
        d.ellipse([bx - 6 * S, by + 12 * S, bx + 6 * S, by + 24 * S], fill=WHITE)
    elif kind == 'record':
        for (sx, sy, sr) in ((-120, -96, 22), (118, -108, 15), (128, 70, 19), (-132, 82, 12)):
            sparkle(d, size / 2 + sx * S, size / 2 + sy * S, sr * S, WHITE)
        for (sx, sy, c) in ((-96, -128, (255, 255, 255, 255)), (96, 120, (255, 255, 255, 230))):
            r = 6 * S
            d.ellipse([size / 2 + sx * S - r, size / 2 + sy * S - r,
                       size / 2 + sx * S + r, size / 2 + sy * S + r], fill=c)
    return img.resize((LAYER, LAYER), Image.LANCZOS)


def background(suffix):
    c1, c2 = VARIANTS[suffix][:2]
    return gradient(LAYER, c1, c2)


def compose(suffix, size, rounded=True):
    bg = background(suffix).resize((size, size), Image.LANCZOS)
    fg = foreground(suffix).resize((size, size), Image.LANCZOS)
    # the visible 72dp window is 2/3 of the 108dp layer: zoom so legacy icons match
    zoom = 1.5
    crop = int(size / zoom)
    off = (size - crop) // 2
    out = Image.alpha_composite(bg, fg).crop((off, off, off + crop, off + crop)).resize((size, size), Image.LANCZOS)
    if rounded:
        mask = Image.new('L', (size * 4, size * 4), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.22), fill=255)
        mask = mask.resize((size, size), Image.LANCZOS)
        out.putalpha(mask)
    return out


def write(path, img):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def write_status_icon():
    """White cube silhouette for the status bar / notifications (alpha only)."""
    S = SS
    size = 24 * 8 * S
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    black = (0, 0, 0, 255)
    clear = (0, 0, 0, 0)
    R = size * 0.46
    draw_cube(d, size / 2, size / 2, R, (black, black, black), clear, S * 2, nodes=False)
    marks = Image.new('RGBA', (size, size), clear)
    draw_cube(ImageDraw.Draw(marks), size / 2, size / 2, R, (clear, clear, clear), WHITE, S * 2, nodes=False)
    img.putalpha(ImageChops.subtract(img.getchannel('A'), marks.getchannel('A')))
    white = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    white.putalpha(img.getchannel('A'))
    for dens, px in {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}.items():
        write(os.path.join(RES, f'drawable-{dens}', 'ic_stat_axon.png'),
              white.resize((px, px), Image.LANCZOS))


def main():
    densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    sheet = Image.new('RGBA', (len(VARIANTS) * 280 + 20, 560), (245, 242, 236, 255))
    for i, suffix in enumerate(VARIANTS):
        name = 'ic_launcher' + suffix
        write(os.path.join(RES, 'mipmap-xxxhdpi', name + '_foreground.png'), foreground(suffix))
        write(os.path.join(RES, 'mipmap-xxxhdpi', name + '_background.png'), background(suffix))
        for dens, px in densities.items():
            write(os.path.join(RES, f'mipmap-{dens}', name + '.png'), compose(suffix, px))
        mono = ''
        if suffix == '':
            write(os.path.join(RES, 'mipmap-xxxhdpi', 'ic_launcher_monochrome.png'),
                  foreground('', mono=True))
            mono = '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        xml = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <background android:drawable="@mipmap/{name}_background"/>\n'
            f'    <foreground android:drawable="@mipmap/{name}_foreground"/>\n'
            f'{mono}'
            '</adaptive-icon>\n'
        )
        os.makedirs(os.path.join(RES, 'mipmap-anydpi-v26'), exist_ok=True)
        with open(os.path.join(RES, 'mipmap-anydpi-v26', name + '.xml'), 'w', newline='\n') as f:
            f.write(xml)
        # preview: rounded legacy art on top, circle mask below
        sheet.paste(compose(suffix, 256), (20 + i * 280, 20), compose(suffix, 256))
        circ = compose(suffix, 256, rounded=False)
        m = Image.new('L', (256 * 4, 256 * 4), 0)
        ImageDraw.Draw(m).ellipse([0, 0, 256 * 4 - 1, 256 * 4 - 1], fill=255)
        circ.putalpha(m.resize((256, 256), Image.LANCZOS))
        sheet.paste(circ, (20 + i * 280, 290), circ)
        # in-app preview used by Settings > Appearance > Living app icon
        key = suffix.lstrip('_') or 'standard'
        write(os.path.join(ASSETS, 'app_icons', key + '.png'), compose(suffix, 192))
        if suffix == '':
            write_status_icon()
            full = compose('', 1024)
            write(os.path.join(ASSETS, 'axon_app_icon_1024.png'), full)
            write(os.path.join(ASSETS, 'axon_app_icon_512.png'), full.resize((512, 512), Image.LANCZOS))
    sheet.convert('RGB').save(os.path.join(HERE, 'preview.png'))
    print('icons written; preview at', os.path.join(HERE, 'preview.png'))


if __name__ == '__main__':
    sys.exit(main())
