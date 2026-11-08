"""Монтаж скриншотов для README и инструкции.

Берёт исходные скриншоты Calculate Linux Cinnamon, добавляет плашку с шагом,
обводки, стрелки, галочки и увеличенные вставки. Метаданные исходников не сохраняются.

Запуск (нужен Pillow):  python docs/tools/annotate_screenshots.py ПАПКА_СО_СКРИНШОТАМИ
Результат: docs/screenshots/*.png (для README) и usb/app/img/*.jpg (для ИНСТРУКЦИЯ.html).
Исходные скриншоты в репозиторий не входят; координаты пометок рассчитаны на них (1920x1080).
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DOCS = os.path.join(ROOT, "docs", "screenshots")
OUT_USB = os.path.join(ROOT, "usb", "app", "img")

S = 2                 # рисуем в 2x, потом уменьшаем (сглаживание)
BAR = 150             # высота плашки сверху, в пикселях исходника
OUT_W = 1600          # ширина PNG для README
USB_W = 1000          # ширина JPEG для инструкции

ACCENT = (255, 77, 46)
GREEN = (34, 197, 94)
DARK = (24, 30, 41)
WHITE = (255, 255, 255)

FONT_DIRS = [r"C:\Windows\Fonts", "/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/dejavu"]


def font(bold, size):
    names = ["segoeuib.ttf", "DejaVuSans-Bold.ttf"] if bold else ["segoeui.ttf", "DejaVuSans.ttf"]
    for d in FONT_DIRS:
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return ImageFont.truetype(p, size * S)
    raise SystemExit("Не найден шрифт с кириллицей (Segoe UI или DejaVu Sans)")


class Shot:
    def __init__(self, path):
        src = Image.open(path).convert("RGB")
        self.w, self.h = src.size
        self.img = Image.new("RGB", (self.w * S, (self.h + BAR) * S), DARK)
        self.img.paste(src.resize((self.w * S, self.h * S), Image.LANCZOS), (0, BAR * S))
        self.d = ImageDraw.Draw(self.img)

    # координаты — в пикселях исходного скриншота (без плашки)
    def xy(self, x, y):
        return (x * S, (y + BAR) * S)

    def box(self, x0, y0, x1, y1):
        return (*self.xy(x0, y0), *self.xy(x1, y1))

    def caption(self, step, title, subtitle=None):
        d = self.d
        r = 46 * S
        cx, cy = 80 * S, (BAR // 2) * S
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ACCENT)
        f = font(True, 50)
        d.text((cx, cy), str(step), font=f, fill=WHITE, anchor="mm")
        tx = 155 * S
        if subtitle:
            d.text((tx, 42 * S), title, font=font(True, 46), fill=WHITE, anchor="lm")
            d.text((tx, 104 * S), subtitle, font=font(False, 32), fill=(200, 208, 222), anchor="lm")
        else:
            d.text((tx, cy), title, font=font(True, 48), fill=WHITE, anchor="lm")

    def ring(self, x0, y0, x1, y1, color=ACCENT, pad=10, ellipse=False):
        b = (x0 - pad, y0 - pad, x1 + pad, y1 + pad)
        bb = self.box(*b)
        shape = self.d.ellipse if ellipse else (lambda *a, **k: self.d.rounded_rectangle(*a, radius=18 * S, **k))
        shape(bb, outline=WHITE, width=13 * S)
        shape(bb, outline=color, width=7 * S)

    def mark(self, x0, y0, x1, y1, color=ACCENT):
        """Полупрозрачная подсветка строки (не закрывает соседний текст)."""
        overlay = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.rounded_rectangle(self.box(x0, y0, x1, y1), radius=6 * S, fill=color + (80,),
                             outline=color + (255,), width=3 * S)
        self.img = Image.alpha_composite(self.img.convert("RGBA"), overlay).convert("RGB")
        self.d = ImageDraw.Draw(self.img)

    def arrow(self, x0, y0, x1, y1, color=ACCENT):
        p0, p1 = self.xy(x0, y0), self.xy(x1, y1)
        ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        head = 34 * S
        base = (p1[0] - head * 0.8 * math.cos(ang), p1[1] - head * 0.8 * math.sin(ang))
        for col, w in ((WHITE, 16), (color, 9)):
            self.d.line((p0, base), fill=col, width=w * S)
        pts = [p1,
               (p1[0] - head * math.cos(ang - 0.45), p1[1] - head * math.sin(ang - 0.45)),
               (p1[0] - head * math.cos(ang + 0.45), p1[1] - head * math.sin(ang + 0.45))]
        self.d.polygon(pts, fill=color, outline=WHITE, width=3 * S)

    def label(self, x, y, text, color=ACCENT, size=34, anchor="lm"):
        f = font(True, size)
        p = self.xy(x, y)
        l, t, r, b = self.d.textbbox(p, text, font=f, anchor=anchor)
        pad = 16 * S
        self.d.rounded_rectangle((l - pad, t - pad, r + pad, b + pad), radius=14 * S,
                                 fill=color, outline=WHITE, width=4 * S)
        self.d.text(p, text, font=f, fill=WHITE, anchor=anchor)

    def check(self, cx, cy, r=30):
        x, y = self.xy(cx, cy)
        r *= S
        self.d.ellipse((x - r - 5 * S, y - r - 5 * S, x + r + 5 * S, y + r + 5 * S), fill=WHITE)
        self.d.ellipse((x - r, y - r, x + r, y + r), fill=GREEN)
        self.d.line([(x - r * 0.45, y + r * 0.02), (x - r * 0.1, y + r * 0.38), (x + r * 0.5, y - r * 0.35)],
                    fill=WHITE, width=9 * S, joint="curve")

    def zoom(self, src_box, dest_xy, k, border=ACCENT):
        """Увеличенная вставка участка (уже с нарисованными пометками)."""
        x0, y0, x1, y1 = src_box
        crop = self.img.crop(self.box(x0, y0, x1, y1))
        cw, ch = int((x1 - x0) * k * S), int((y1 - y0) * k * S)
        crop = crop.resize((cw, ch), Image.LANCZOS)
        dx, dy = self.xy(*dest_xy)
        shadow = Image.new("L", (cw + 80 * S, ch + 80 * S), 0)
        ImageDraw.Draw(shadow).rounded_rectangle((40 * S, 40 * S, cw + 40 * S, ch + 40 * S), 20 * S, fill=150)
        shadow = shadow.filter(ImageFilter.GaussianBlur(18 * S))
        self.img.paste((0, 0, 0), (dx - 30 * S, dy - 26 * S), shadow)
        self.img.paste(crop, (dx, dy))
        b = 6 * S
        self.d.rounded_rectangle((dx - b, dy - b, dx + cw + b, dy + ch + b), radius=10 * S, outline=WHITE, width=b)
        self.d.rounded_rectangle((dx - b, dy - b, dx + cw + b, dy + ch + b), radius=10 * S, outline=border, width=4 * S)
        return (dest_xy[0], dest_xy[1], dest_xy[0] + cw / S, dest_xy[1] + ch / S)

    def save(self, name):
        final = self.img.resize((OUT_W, round(self.img.height * OUT_W / self.img.width)), Image.LANCZOS)
        final.save(os.path.join(OUT_DOCS, name + ".png"), optimize=True)
        usb = self.img.resize((USB_W, round(self.img.height * USB_W / self.img.width)), Image.LANCZOS)
        usb.save(os.path.join(OUT_USB, name + ".jpg"), quality=82, optimize=True, progressive=True)
        return final


def main(src_dir):
    os.makedirs(OUT_DOCS, exist_ok=True)
    os.makedirs(OUT_USB, exist_ok=True)

    def src(t):
        return os.path.join(src_dir, "Снимок экрана от 2026-11-04 %s.png" % t)

    shots = {}

    # 1. Папка на рабочем столе
    s = Shot(src("17-45-33"))
    s.caption(1, "Скопируйте папку CLDC-Russian-Default-USB на рабочий стол",
              "С флешки (FAT32/NTFS) — простым перетаскиванием в Nemo")
    s.ring(12, 236, 142, 352)
    z = s.zoom((0, 226, 160, 362), (360, 230), 2.6)
    s.arrow(160, 294, z[0] - 14, 294)
    s.label(z[0], z[3] + 50, "Готово: папка на рабочем столе", anchor="lm")
    shots["01-copy-folder"] = s.save("01-copy-folder")

    # 2. Содержимое папки
    s = Shot(src("17-43-56"))
    s.caption(2, "Откройте папку и дважды щёлкните «Установить»",
              "Пароль, sudo и интернет не нужны")
    s.ring(724, 160, 828, 270)
    z = s.zoom((190, 152, 990, 296), (330, 430), 1.6)
    s.label(1000, 360, "2× щелчок", size=36)
    s.arrow(982, 352, 845, 262)
    s.label(z[0], z[3] + 50, "«Установить» — ярлык установки, «Проверить установку» — ярлык проверки")
    shots["02-open-installer"] = s.save("02-open-installer")

    # 3. Диалог «Сомнительная кнопка запуска»
    s = Shot(src("17-47-02"))
    s.caption(3, "Один раз нажмите «Сделать доверенной»",
              "Это обычный вопрос Nemo о ярлыках с флешки; защиту отключать не нужно")
    s.ring(872, 649, 1050, 681)
    z = s.zoom((688, 512, 1232, 684), (1010, 215), 1.6)
    s.arrow(1245, 600, 1330, z[3] + 16)
    s.check(961, 735)
    s.label(1000, 735, "Нажмите эту кнопку", size=34)
    s.label(688, 820, "Можно и «Запустить всё равно» — сработает, но спросит снова", color=DARK, size=28)
    shots["03-trust-launcher"] = s.save("03-trust-launcher")

    # 4. Значок стал клавиатурой
    s = Shot(src("17-47-13"))
    s.caption(4, "Значок сменился на «Установить» с клавиатурой",
              "Если окно установки не открылось само — дважды щёлкните значок ещё раз")
    s.ring(726, 168, 824, 258)
    s.check(840, 175)
    z = s.zoom((590, 152, 960, 296), (540, 400), 2.3)
    s.arrow(775, 270, 775, z[1] - 14)
    shots["04-trusted-icon"] = s.save("04-trusted-icon")

    # 5. Установка завершена
    s = Shot(src("17-47-23"))
    s.caption(5, "«ГОТОВО!» — русская раскладка стала основной",
              "Окно ждёт Enter и не закроется само, если что-то пойдёт не так")
    s.ring(0, 843, 585, 988, color=GREEN, pad=8)
    s.check(620, 880)
    s.mark(0, 302, 700, 338)
    s.label(735, 320, "RU первая, US вторая — применено сразу", size=30)
    s.ring(1780, 6, 1806, 32, pad=8, ellipse=True)
    z = s.zoom((1545, 0, 1915, 40), (800, 470), 2.9)
    s.arrow(1793, 50, z[2] - 120, z[1] - 12)
    s.label(z[0], z[3] + 50, "Индикатор на панели: ru", size=34)
    shots["05-install-done"] = s.save("05-install-done")

    # 6. Ярлык проверки
    s = Shot(src("17-48-33"))
    s.caption(6, "Проверка: дважды щёлкните «Проверить установку»",
              "Например, после перезагрузки. Первый раз тоже «Сделать доверенной»")
    s.ring(594, 160, 692, 272)
    z = s.zoom((190, 152, 990, 296), (330, 430), 1.6)
    s.arrow(643, 285, 643, z[1] - 14)
    shots["06-open-check"] = s.save("06-open-check")

    # 7. Проверка пройдена
    s = Shot(src("17-48-08"))
    s.caption(7, "«ВСЁ В ПОРЯДКЕ» — RU включается по умолчанию",
              "sources: ru, us · current: 0 · автозапуск на месте")
    s.ring(0, 646, 585, 716, color=GREEN, pad=8)
    s.check(620, 680)
    s.mark(0, 320, 662, 338)
    s.label(720, 329, "Автозапуск: срабатывает при каждом входе", size=30)
    s.mark(0, 356, 420, 392)
    s.arrow(430, 380, 700, 425)
    s.label(720, 425, "RU первая, активна раскладка №0 (RU)", size=30)
    shots["07-check-ok"] = s.save("07-check-ok")

    make_hero(src)
    print("Готово:", OUT_DOCS, OUT_USB)


def make_hero(src):
    """Обложка 1280x640: три шага (подходит и как social preview GitHub)."""
    W, H = 1280 * S, 640 * S
    img = Image.new("RGB", (W, H), DARK)
    d = ImageDraw.Draw(img)
    d.text((60 * S, 62 * S), "CLDC-Russian-Default", font=font(True, 54), fill=WHITE, anchor="lm")
    d.text((60 * S, 122 * S), "Русская раскладка по умолчанию на десятках Linux-ноутбуков",
           font=font(False, 30), fill=(200, 208, 222), anchor="lm")
    d.text((60 * S, 166 * S), "Calculate Linux · Cinnamon · флешка · двойной щелчок · без sudo",
           font=font(False, 24), fill=(150, 160, 178), anchor="lm")

    panels = [
        ("17-45-33", (0, 205, 340, 425), "1. Скопировать папку"),
        ("17-47-13", (590, 150, 960, 390), "2. Дважды щёлкнуть"),
        ("17-47-23", (0, 690, 600, 1080), "3. ГОТОВО!"),
    ]
    pw, ph, gap, top = 360 * S, 300 * S, 50 * S, 230 * S
    x = 60 * S
    for i, (t, box, title) in enumerate(panels):
        iw, ih = pw - 24 * S, ph - 82 * S
        im = ImageOps.fit(Image.open(src(t)).convert("RGB").crop(box), (iw, ih), Image.LANCZOS)
        d.rounded_rectangle((x, top, x + pw, top + ph), radius=22 * S, fill=(36, 44, 58))
        mask = Image.new("L", (iw, ih), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, iw, ih), radius=14 * S, fill=255)
        img.paste(im, (x + 12 * S, top + 12 * S), mask)
        col = GREEN if i == 2 else ACCENT
        d.text((x + pw // 2, top + ph - 35 * S), title, font=font(True, 28), fill=col, anchor="mm")
        if i < 2:
            ax = x + pw + gap // 2
            ay = top + ph // 2
            d.polygon([(ax - 14 * S, ay - 22 * S), (ax + 14 * S, ay), (ax - 14 * S, ay + 22 * S)], fill=ACCENT)
        x += pw + gap
    d.text((60 * S, 590 * S), "≈ 5 секунд на ноутбук вместо ручной настройки каждого",
           font=font(True, 26), fill=WHITE, anchor="lm")
    img = img.resize((1280, 640), Image.LANCZOS)
    img.save(os.path.join(OUT_DOCS, "00-hero.png"), optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
