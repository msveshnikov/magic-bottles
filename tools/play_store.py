"""Google Play store graphics -> renders/play/.

python tools/play_store.py [--no-shots]
  icon_512.png               app icon (assets/ui/icon.png)
  feature_{ru,en}_1024x500.png  feature graphic: painted world + icon + title
  {ru,en}_N_*.png            phone screenshots 1080x1920 rendered by the game (-- --storeshots)
"""
import glob, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "renders", "play")
RAW = os.path.join(OUT, "raw")
GODOT = os.path.expanduser("~/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe")
TITLE_FONT = os.path.join(ROOT, "assets", "fonts", "Lobster.ttf")
BODY_FONT = os.path.join(ROOT, "assets", "fonts", "Nunito.ttf")


def shots():
    for f in glob.glob(os.path.join(RAW, "*.png")):
        os.remove(f)
    for lang in ("ru", "en"):
        subprocess.run([GODOT, "--path", ROOT, "--resolution", "1080x1920", "--quit-after", "20000",
                        "--", "--storeshots", "--lang", lang], check=False, capture_output=True)
    for f in sorted(glob.glob(os.path.join(RAW, "*.png"))):
        im = Image.open(f)
        assert im.size == (1080, 1920), (f, im.size)
        im.convert("RGB").save(os.path.join(OUT, os.path.basename(f)))
        print("shot", os.path.basename(f))


def icon():
    Image.open(os.path.join(ROOT, "assets", "ui", "icon.png")).convert("RGB").resize((512, 512), Image.LANCZOS) \
        .save(os.path.join(OUT, "icon_512.png"))


def feature(lang):
    w, h = 1024, 500
    bg = Image.open(os.path.join(ROOT, "concept", "bg_workshop.png")).convert("RGB")
    s = bg.width / w
    bg = bg.resize((w, round(bg.height / s)), Image.LANCZOS)
    top = (bg.height - h) // 2
    bg = bg.crop((0, top, w, top + h))
    shade = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shade).rectangle((330, 0, w, h), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(60))
    bg = Image.composite(Image.new("RGB", (w, h), (14, 6, 30)), bg, shade)
    ic = Image.open(os.path.join(ROOT, "assets", "ui", "icon.png")).convert("RGB").resize((330, 330), Image.LANCZOS)
    m = Image.new("L", ic.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 329, 329), 64, fill=255)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((40, 75, 400, 435), 80, fill=(255, 200, 90, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(28))
    bg = bg.convert("RGBA")
    bg.alpha_composite(glow)
    bg = bg.convert("RGB")
    bg.paste(ic, (55, 85), m)
    d = ImageDraw.Draw(bg)
    title = ["Волшебные", "бутылочки"] if lang == "ru" else ["Magic", "Bottles"]
    ft = ImageFont.truetype(TITLE_FONT, 96)
    y = 60
    for line in title:
        d.text((440, y), line, font=ft, fill=(255, 222, 120), stroke_width=6, stroke_fill=(30, 10, 50))
        y += 110
    fb = ImageFont.truetype(BODY_FONT, 34)
    try:
        fb.set_variation_by_axes([850])
    except Exception:
        pass
    sub = "Разлей зелья по цветам!" if lang == "ru" else "Sort the glowing potions!"
    d.text((446, 300), sub, font=fb, fill=(240, 236, 255), stroke_width=3, stroke_fill=(20, 8, 40))
    sub2 = "120 уровней · 6 миров · без рекламы" if lang == "ru" else "120 levels · 6 worlds · no ads"
    fb2 = ImageFont.truetype(BODY_FONT, 28)
    try:
        fb2.set_variation_by_axes([850])
    except Exception:
        pass
    d.text((446, 360), sub2, font=fb2, fill=(255, 205, 90), stroke_width=3, stroke_fill=(20, 8, 40))
    bg.save(os.path.join(OUT, f"feature_{lang}_1024x500.png"))
    print("feature", lang)


if __name__ == "__main__":
    os.makedirs(RAW, exist_ok=True)
    icon()
    feature("ru")
    feature("en")
    if "--no-shots" not in sys.argv:
        shots()
