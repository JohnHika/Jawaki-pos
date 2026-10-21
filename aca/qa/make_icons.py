"""Generate ACA launcher icons (legacy PNG, adaptive foreground + monochrome) from the brand mark."""
import os
from PIL import Image, ImageDraw

RES = r"C:\Projects\POS\pos-system\aca\android\app\src\main\res"
INK = (11, 10, 15, 255)
C1 = (255, 161, 102)  # FFA166
C2 = (224, 97, 30)    # E0611E
SS = 4                 # supersampling


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(C1[i] + (C2[i] - C1[i]) * t) for i in range(3))
    return img.convert("RGBA")


def glyph_layer(canvas, scale, color):
    """Draw the A + counter onto a transparent canvas; scale = px per mark unit; centred."""
    layer = Image.new("RGBA", (canvas * SS, canvas * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    s = scale * SS
    ox = canvas * SS / 2 - 50 * s
    oy = canvas * SS / 2 - 50 * s
    w = int(11 * s)

    def P(x, y):
        return (ox + x * s, oy + y * s)

    pts = [P(27, 76), P(50, 24), P(73, 76)]
    d.line(pts, fill=color, width=w, joint="curve")
    d.line([P(37, 60), P(63, 60)], fill=color, width=w)
    for (x, y) in [P(27, 76), P(73, 76), P(37, 60), P(63, 60), P(50, 24)]:
        r = w / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return layer.resize((canvas, canvas), Image.LANCZOS)


DENS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

for name, m in DENS.items():
    d = os.path.join(RES, f"mipmap-{name}")
    os.makedirs(d, exist_ok=True)

    # adaptive layers: 108dp canvas, glyph ~40% of it (inside the 66% safe zone)
    cv = int(108 * m)
    sc = 0.40 * cv / 63
    glyph_layer(cv, sc, INK).save(os.path.join(d, "ic_launcher_foreground.png"))
    glyph_layer(cv, sc, (255, 255, 255, 255)).save(os.path.join(d, "ic_launcher_monochrome.png"))

    # legacy square-with-rounded-corners icon: 48dp
    lg = int(48 * m)
    tile = gradient(lg * SS)
    mask = Image.new("L", (lg * SS, lg * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, lg * SS - 1, lg * SS - 1], radius=int(0.24 * lg * SS), fill=255)
    tile.putalpha(mask)
    g = glyph_layer(lg, lg / 100 * 0.92, INK).resize((lg * SS, lg * SS), Image.LANCZOS)
    tile.alpha_composite(g)
    tile.resize((lg, lg), Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))
    # round variant for launchers that ask for it
    tile.resize((lg, lg), Image.LANCZOS).save(os.path.join(d, "ic_launcher_round.png"))

os.makedirs(os.path.join(RES, "drawable"), exist_ok=True)
open(os.path.join(RES, "drawable", "ic_launcher_background.xml"), "w", encoding="utf-8").write(
    """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient
        android:angle="315"
        android:startColor="#FFFFA166"
        android:endColor="#FFE0611E" />
</shape>
"""
)
os.makedirs(os.path.join(RES, "mipmap-anydpi-v26"), exist_ok=True)
open(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), "w", encoding="utf-8").write(
    """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
)
print("icons written")

# preview sheet for visual QA
prev = Image.new("RGBA", (1000, 360), (24, 22, 30, 255))
x = 20
for name in ["xxxhdpi"]:
    d = os.path.join(RES, f"mipmap-{name}")
    fg = Image.open(os.path.join(d, "ic_launcher_foreground.png"))
    bg = gradient(432)
    comp = bg.copy()
    comp.alpha_composite(fg)
    m = Image.new("L", (432, 432), 0)
    ImageDraw.Draw(m).ellipse([0, 0, 431, 431], fill=255)
    circ = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    circ.paste(comp, (0, 0), m)
    prev.alpha_composite(circ.resize((300, 300)), (20, 30))
    leg = Image.open(os.path.join(d, "ic_launcher.png")).resize((192, 192))
    prev.alpha_composite(leg, (360, 30))
    mono = Image.open(os.path.join(d, "ic_launcher_monochrome.png")).resize((192, 192))
    bgm = Image.new("RGBA", (192, 192), (60, 58, 70, 255))
    bgm.alpha_composite(mono)
    prev.alpha_composite(bgm, (600, 30))
prev.save(os.path.join(os.environ.get("TEMP", "."), "aca_icon_preview.png"))
print(os.path.join(os.environ.get("TEMP", "."), "aca_icon_preview.png"))
