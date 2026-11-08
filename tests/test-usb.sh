#!/usr/bin/env bash
# Проверки USB-пакета: сборка, состав ZIP и запуск ярлыков без настоящего Cinnamon.
# gsettings подменяется моком, HOME — временным каталогом. GUI (Nemo) здесь не проверяется.
# Запуск: bash tests/test-usb.sh
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MOCK_BIN="$ROOT/tests/mock-bin"
PKG="$ROOT/dist/CLDC-Russian-Default-USB"
ZIP="$ROOT/dist/CLDC-Russian-Default-USB.zip"
ORIG_PATH=$PATH
PASS=0
FAIL=0
IS=org.cinnamon.desktop.input-sources

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '       %s\n' "$2"; }
assert_eq() { if [[ $2 == "$3" ]]; then pass "$1"; else fail "$1" "ожидалось: [$2], получено: [$3]"; fi; }
assert_true() { local n=$1; shift; if "$@"; then pass "$n"; else fail "$n"; fi; }
assert_false() { local n=$1; shift; if "$@"; then fail "$n"; else pass "$n"; fi; }
has() { grep -qF -- "$1" "$T/out"; }

setup() {
  T=$(mktemp -d)
  export HOME="$T/home" MOCK_GS_DIR="$T/gs"
  mkdir -p "$HOME" "$MOCK_GS_DIR/$IS"
  unset XDG_CONFIG_HOME XDG_STATE_HOME DISPLAY WAYLAND_DISPLAY CLDC_GSETTINGS CLDC_USB_TERMINALS
  export PATH="$MOCK_BIN:$ORIG_PATH"
  export XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11
  export CLDC_RECHECK_DELAYS=0 CLDC_ALLOW_ROOT=1 CLDC_USB_SKIP_OS_CHECK=1
  export CLDC_USB_IN_TERMINAL=1 CLDC_USB_NO_PAUSE=1
  printf '%s\n' "[('xkb', 'us'), ('xkb', 'ru')]" >"$MOCK_GS_DIR/$IS/sources"
  printf '%s\n' "uint32 1" >"$MOCK_GS_DIR/$IS/current"
  # копия папки там, где её запустит пользователь: пробелы и кириллица в пути
  DESK="$T/Рабочий стол/CLDC USB копия"
  mkdir -p "${DESK%/*}"
  cp -r "$PKG" "$DESK"
  find "$DESK" -type f -exec chmod 644 {} +   # как после копирования с FAT32
}
teardown() { rm -rf "$T"; }

# Выполнить Exec из .desktop так же, как GLib/Nemo: разэкранировать «\\», подставить %k, разобрать как sh.
run_desktop() {
  local file=$1 line q
  line=$(grep '^Exec=' "$file")
  line=${line#Exec=}
  line=${line//\\\\/\\}
  q="'$file'"
  line=${line//%k/$q}
  eval "set -- $line"
  "$@" </dev/null >"$T/out" 2>&1
}

echo "== Сборка"
bash "$ROOT/usb/build-usb.sh" >/dev/null 2>&1; rc=$?
assert_eq "build-usb.sh: код 0" 0 "$rc"
assert_true "папка собрана" test -d "$PKG"
assert_true "ZIP собран" test -s "$ZIP"
assert_true "программа в пакете не изменена" cmp -s "$ROOT/cldc-russian-default" "$PKG/app/cldc-russian-default"
assert_true "запускатель в пакете не изменён" cmp -s "$ROOT/usb/app/usb-launcher.sh" "$PKG/app/usb-launcher.sh"
no_cr() { local f; while IFS= read -r -d '' f; do [[ -z $(tr -cd '\r' <"$f") ]] || return 1; done < <(find "$PKG" -type f ! -name '*.jpg' -print0); }
assert_true "нет CRLF в пакете" no_cr

PY=""
for p in python3 python; do command -v "$p" >/dev/null 2>&1 && "$p" -c 'import zipfile' 2>/dev/null && { PY=$p; break; }; done
if [[ -n $PY ]]; then
  zp=$ZIP; command -v cygpath >/dev/null 2>&1 && zp=$(cygpath -w "$ZIP")
  listing=$("$PY" -I -X utf8 -c '
import sys, zipfile
for i in zipfile.ZipFile(sys.argv[1]).infolist():
    if not i.filename.endswith("/"):
        print("%o %d %s" % (i.external_attr >> 16 & 0o777, i.flag_bits >> 11 & 1, i.filename))
' "$zp" | tr -d '\r')
  assert_true "ZIP: «Установить.desktop» 755" grep -qxF "755 1 CLDC-Russian-Default-USB/Установить.desktop" <<<"$listing"
  assert_true "ZIP: программа 755" grep -qxF "755 0 CLDC-Russian-Default-USB/app/cldc-russian-default" <<<"$listing"
  assert_true "ZIP: инструкция 644" grep -qxF "644 1 CLDC-Russian-Default-USB/ИНСТРУКЦИЯ.html" <<<"$listing"
  assert_true "ZIP: картинка инструкции 644" grep -qxF "644 0 CLDC-Russian-Default-USB/app/img/03-trust-launcher.jpg" <<<"$listing"
  assert_eq "ZIP: 14 файлов" 14 "$(wc -l <<<"$listing" | tr -d ' ')"
else
  echo "  (python не найден — проверка содержимого ZIP пропущена)"
fi

echo "== Ярлык «Установить» (путь с пробелами и кириллицей, без прав на запуск)"
setup
run_desktop "$DESK/Установить.desktop"; rc=$?
assert_eq "код 0" 0 "$rc"
assert_true "сообщение «ГОТОВО!»" has "ГОТОВО! Установка выполнена успешно."
assert_true "status выполнен" has "Итог: OK"
assert_eq "RU первая" "[('xkb', 'ru'), ('xkb', 'us')]" "$(cat "$MOCK_GS_DIR/$IS/sources")"
assert_true "автозапуск создан" test -f "$HOME/.config/autostart/cldc-russian-default.desktop"
assert_true "отчёт сохранён" grep -qF "ГОТОВО!" "$HOME/.local/state/cldc-russian-default/usb-install-report.txt"

echo "== Ярлык «Проверить установку»"
run_desktop "$DESK/Проверить установку.desktop"; rc=$?
assert_eq "код 0" 0 "$rc"
assert_true "сообщение «ВСЁ В ПОРЯДКЕ»" has "ВСЁ В ПОРЯДКЕ"

echo "== Резервный «Установить.sh» (повторная установка)"
(cd "$T" && bash "$DESK/Установить.sh" </dev/null >"$T/out" 2>&1); rc=$?
assert_eq "код 0" 0 "$rc"
assert_true "сообщение «ГОТОВО!»" has "ГОТОВО!"
(cd "$DESK" && bash app/usb-launcher.sh check </dev/null >"$T/out" 2>&1); rc=$?
assert_eq "терминальный способ check: код 0" 0 "$rc"
teardown

echo "== Ошибки"
setup
run_desktop "$DESK/Проверить установку.desktop"; rc=$?
assert_eq "проверка до установки: код 1" 1 "$rc"
assert_true "сообщение «НЕ УСТАНОВЛЕНО»" has "НЕ УСТАНОВЛЕНО"
touch "$MOCK_GS_DIR/$IS/.ro-sources"
run_desktop "$DESK/Установить.desktop"; rc=$?
assert_eq "заблокированный ключ: код 1" 1 "$rc"
assert_true "сообщение об ошибке" has "ОШИБКА: установка выполнена, но проверка показала проблему"
teardown
setup
rm -f "$DESK/app/cldc-russian-default"
run_desktop "$DESK/Установить.desktop"; rc=$?
assert_eq "нет файла программы: код 1" 1 "$rc"
assert_true "понятное сообщение" has "не найден файл программы"
teardown
setup
sed -i 's/$/\r/' "$DESK/app/cldc-russian-default"
run_desktop "$DESK/Установить.desktop"; rc=$?
assert_eq "программа с CRLF: всё равно код 0" 0 "$rc"
assert_true "предупреждение о CRLF" has "переводами строк Windows"
teardown

echo "== Без окна терминала (резервный показ отчёта)"
setup
unset CLDC_USB_IN_TERMINAL
export CLDC_USB_TERMINALS="no-such-terminal-cldc"
run_desktop "$DESK/Установить.desktop"; rc=$?
assert_eq "код 0" 0 "$rc"
assert_true "отчёт содержит «ГОТОВО!»" grep -qF "ГОТОВО!" "$HOME/.local/state/cldc-russian-default/usb-install-report.txt"
teardown

echo
echo "Итого: $PASS пройдено, $FAIL с ошибками"
(( FAIL == 0 ))
