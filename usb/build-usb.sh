#!/usr/bin/env bash
# Сборка USB-пакета:
#   dist/CLDC-Russian-Default-USB/       — папка для копирования на флешку
#   dist/CLDC-Russian-Default-USB.zip    — та же папка в ZIP (права Linux 0755, имена в UTF-8)
# Запуск: bash usb/build-usb.sh   (Linux или Git Bash на Windows; для ZIP нужен zip или python)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/usb"
DIST="$ROOT/dist"
NAME="CLDC-Russian-Default-USB"
OUT="$DIST/$NAME"
ZIP="$DIST/$NAME.zip"

# Всё, что попадает в пакет, и ничего больше.
FILES=(
  "Установить.desktop"
  "Проверить установку.desktop"
  "Установить.sh"
  "ИНСТРУКЦИЯ.html"
  "ИНСТРУКЦИЯ.txt"
  "app/usb-launcher.sh"
)
EXECUTABLE=(
  "Установить.desktop"
  "Проверить установку.desktop"
  "Установить.sh"
  "app/usb-launcher.sh"
  "app/cldc-russian-default"
)

fail() { printf 'ОШИБКА СБОРКИ: %s\n' "$*" >&2; exit 1; }
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

echo "Сборка $NAME"
rm -rf -- "$OUT" "$ZIP"
mkdir -p "$OUT/app"
for f in "${FILES[@]}"; do
  [[ -f $SRC/$f ]] || fail "нет исходного файла usb/$f"
  cp -- "$SRC/$f" "$OUT/$f"
done
cp -- "$ROOT/cldc-russian-default" "$OUT/app/cldc-russian-default"
find "$OUT" -type f -exec chmod 644 {} +
for f in "${EXECUTABLE[@]}"; do chmod 755 "$OUT/$f"; done

echo "Проверки:"
# 1. Точный состав пакета
expected=$(printf '%s\n' "${FILES[@]}" "app/cldc-russian-default" | sort)
actual=$(cd "$OUT" && find . -type f | sed 's|^\./||' | sort)
[[ $expected == "$actual" ]] || fail "лишние или недостающие файлы:"$'\n'"$actual"
echo "  состав: $(wc -l <<<"$actual" | tr -d ' ') файлов"

# 2. Переводы строк Linux и без BOM
while IFS= read -r f; do
  # tr, а не grep: grep в Git Bash на Windows не видит \r
  [[ -z $(tr -cd '\r' <"$OUT/$f") ]] || fail "CRLF в $f"
  [[ $(head -c 3 "$OUT/$f" | od -An -tx1 | tr -d ' \n') != efbbbf ]] || fail "BOM в $f"
done <<<"$actual"
echo "  переводы строк: LF, без BOM"

# 3. Синтаксис Bash
for f in "Установить.sh" "app/usb-launcher.sh" "app/cldc-russian-default"; do
  bash -n "$OUT/$f" || fail "синтаксис $f"
done
echo "  bash -n: OK"

# 4. Ярлыки
for f in "Установить.desktop" "Проверить установку.desktop"; do
  head -n 1 "$OUT/$f" | grep -qx '\[Desktop Entry\]' || fail "$f: нет [Desktop Entry]"
  grep -q '^Type=Application$' "$OUT/$f" || fail "$f: нет Type=Application"
  grep -q '^Exec=sh -c ".*app/usb-launcher.sh.*" %k$' "$OUT/$f" || fail "$f: неверный Exec"
done
echo "  ярлыки .desktop: OK"

# 5. Никаких секретов
if grep -rIniE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|BEGIN [A-Z ]*PRIVATE KEY|passw(or)?d[[:space:]]*=' "$OUT"; then
  fail "найдено похожее на пароль или токен"
fi
echo "  секреты: не найдены"

# ZIP: zip (Linux) или python zipfile (Windows). Права 0755 сохраняются для unzip/«Архиватора».
if command -v zip >/dev/null 2>&1; then
  (cd "$DIST" && zip -q -r -X "$NAME.zip" "$NAME")
else
  PY=""
  for p in python3 python py; do
    if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import zipfile' >/dev/null 2>&1; then PY=$p; break; fi
  done
  [[ -n $PY ]] || fail "для ZIP нужен zip или python"
  "$PY" -I -X utf8 - "$(winpath "$DIST")" "$NAME" "${EXECUTABLE[@]}" <<'PY'
import os, sys, time, zipfile
dist, name, executable = sys.argv[1], sys.argv[2], set(sys.argv[3:])
base = os.path.join(dist, name)
stamp = time.localtime()[:6]
with zipfile.ZipFile(os.path.join(dist, name + ".zip"), "w", zipfile.ZIP_DEFLATED) as z:
    for top, dirs, files in os.walk(base):
        dirs.sort()
        rel_top = os.path.relpath(top, base).replace(os.sep, "/")
        rel_top = "" if rel_top == "." else rel_top + "/"
        d = zipfile.ZipInfo(name + "/" + rel_top, stamp)
        d.create_system = 3
        d.external_attr = (0o40755 << 16) | 0x10
        z.writestr(d, b"")
        for f in sorted(files):
            rel = rel_top + f
            info = zipfile.ZipInfo(name + "/" + rel, stamp)
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o100755 if rel in executable else 0o100644) << 16
            with open(os.path.join(top, f), "rb") as fh:
                z.writestr(info, fh.read())
PY
fi
[[ -s $ZIP ]] || fail "ZIP не создан"

echo "Готово:"
echo "  папка: $OUT"
echo "  ZIP:   $ZIP ($(wc -c <"$ZIP" | tr -d ' ') байт)"
command -v sha256sum >/dev/null 2>&1 && echo "  SHA256: $(sha256sum "$ZIP" | cut -d' ' -f1)"
exit 0
