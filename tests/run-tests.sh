#!/usr/bin/env bash
# Простые проверки cldc-russian-default без настоящего Cinnamon:
# gsettings подменяется моком tests/mock-bin/gsettings, HOME — временным каталогом.
# Запуск: bash tests/run-tests.sh
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/cldc-russian-default"
MOCK_BIN="$ROOT/tests/mock-bin"
ORIG_PATH=$PATH
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '       %s\n' "$2"; }
assert_eq() {
  if [[ $2 == "$3" ]]; then pass "$1"; else fail "$1" "ожидалось: [$2], получено: [$3]"; fi
}
assert_true() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
assert_false() { local name=$1; shift; if "$@"; then fail "$name"; else pass "$name"; fi; }

setup() {
  T=$(mktemp -d)
  export HOME="$T/home" MOCK_GS_DIR="$T/gs"
  mkdir -p "$HOME" "$MOCK_GS_DIR"
  unset XDG_CONFIG_HOME XDG_STATE_HOME DISPLAY WAYLAND_DISPLAY GSETTINGS_BACKEND CLDC_GSETTINGS
  export PATH="$MOCK_BIN:$ORIG_PATH"
  export XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11
  export CLDC_RECHECK_DELAYS=0 CLDC_WAIT_TIMEOUT=1 CLDC_ALLOW_ROOT=1
  chmod +x "$MOCK_BIN/gsettings" 2>/dev/null || true
}
teardown() { rm -rf "$T"; }
mk() { mkdir -p "$MOCK_GS_DIR/$1"; printf '%s\n' "$3" >"$MOCK_GS_DIR/$1/$2"; }
gsv() { cat "$MOCK_GS_DIR/$1/$2"; }
sets() { [[ -f $MOCK_GS_DIR/.setlog ]] && wc -l <"$MOCK_GS_DIR/.setlog" | tr -d ' ' || echo 0; }
run() { bash "$SCRIPT" "$@" >"$T/out" 2>&1; }
nbackups() { local n=0 f; for f in "$HOME/.local/state/cldc-russian-default/backups"/[0-9]*.tsv; do [[ -f $f ]] && n=$((n + 1)); done; echo $n; }
lib() { ( source "$SCRIPT"; "$@" ); }
quiet() { "$@" >/dev/null 2>&1; }

IS=org.cinnamon.desktop.input-sources
KBD=org.gnome.libgnomekbd.keyboard
KBDD=org.gnome.libgnomekbd.desktop
mk_cinnamon() {
  mk $IS sources "$1"
  mk $IS current "$2"
  mk $IS xkb-options "['grp_led:scroll', 'compose:ralt']"
  mk org.cinnamon.desktop.keybindings.wm switch-input-source "['<Super>space']"
}

echo "== Синтаксис (bash -n)"
for f in "$SCRIPT" "$MOCK_BIN/gsettings" "$ROOT/tests/run-tests.sh"; do
  assert_true "bash -n ${f#"$ROOT"/}" bash -n "$f"
done

echo "== Разбор и порядок раскладок"
reorder_src() { lib desired_sources "$1"; }
assert_eq "us,ru -> ru,us" "[('xkb', 'ru'), ('xkb', 'us')]" "$(reorder_src "[('xkb', 'us'), ('xkb', 'ru')]")"
assert_eq "уже ru,us" "[('xkb', 'ru'), ('xkb', 'us')]" "$(reorder_src "[('xkb', 'ru'), ('xkb', 'us')]")"
assert_eq "посторонние сохраняются" "[('xkb', 'ru'), ('xkb', 'us'), ('xkb', 'de'), ('ibus', 'mozc-jp')]" \
  "$(reorder_src "[('xkb', 'de'), ('xkb', 'us'), ('ibus', 'mozc-jp'), ('xkb', 'ru')]")"
assert_eq "вариант ru сохраняется" "[('xkb', 'ru+phonetic'), ('xkb', 'us')]" "$(reorder_src "[('xkb', 'us'), ('xkb', 'ru+phonetic')]")"
assert_eq "точный us важнее варианта" "[('xkb', 'ru'), ('xkb', 'us'), ('xkb', 'us+intl')]" \
  "$(reorder_src "[('xkb', 'us+intl'), ('xkb', 'us'), ('xkb', 'ru')]")"
assert_eq "нет ru -> добавить" "[('xkb', 'ru'), ('xkb', 'us')]" "$(reorder_src "[('xkb', 'us')]")"
assert_eq "нет us -> добавить" "[('xkb', 'ru'), ('xkb', 'us')]" "$(reorder_src "[('xkb', 'ru')]")"
assert_eq "пустой список" "[('xkb', 'ru'), ('xkb', 'us')]" "$(reorder_src "@a(ss) []")"
assert_false "мусор не разбирается" quiet lib parse_sources "garbage"
assert_false "битый кортеж не разбирается" quiet lib parse_sources "[('xkb', 'us'), oops]"
assert_eq "libgnomekbd strv" "['ru\\tphonetic', 'us', 'de']" "$(lib desired_strv "['us', 'de', 'ru\\tphonetic']")"
assert_eq "libgnomekbd пустой" "['ru', 'us']" "$(lib desired_strv "@as []")"

echo "== apply: org.cinnamon.desktop.input-sources"
setup
mk_cinnamon "[('xkb', 'us'), ('xkb', 'ru')]" "uint32 1"
mk $KBD layouts "['us']"
run apply; rc=$?
assert_eq "код возврата 0" 0 "$rc"
assert_eq "sources: RU первая" "[('xkb', 'ru'), ('xkb', 'us')]" "$(gsv $IS sources)"
assert_eq "current = 0" "uint32 0" "$(gsv $IS current)"
assert_eq "xkb-options не тронуты" "['grp_led:scroll', 'compose:ralt']" "$(gsv $IS xkb-options)"
assert_eq "Super+Space не тронут" "['<Super>space']" "$(gsv org.cinnamon.desktop.keybindings.wm switch-input-source)"
assert_eq "libgnomekbd не тронут" "['us']" "$(gsv $KBD layouts)"
orig="$HOME/.local/state/cldc-russian-default/backups/original.tsv"
assert_true "исходная копия создана" test -f "$orig"
assert_true "в копии старый sources" grep -qF "[('xkb', 'us'), ('xkb', 'ru')]" "$orig"
before=$(sets); nb=$(nbackups)
run apply; rc=$?
assert_eq "повтор: код 0" 0 "$rc"
assert_eq "повтор: ничего не записано" "$before" "$(sets)"
assert_eq "повтор: новых копий нет" "$nb" "$(nbackups)"
run status; rc=$?
assert_eq "status без автозапуска -> 3" 3 "$rc"
assert_true "status: OK по раскладкам" grep -q 'Итог: OK' "$T/out"
teardown

echo "== apply: mru-sources и dry-run"
setup
mk_cinnamon "[('xkb', 'us'), ('xkb', 'ru')]" "uint32 0"
mk $IS mru-sources "[('xkb', 'us'), ('xkb', 'ru')]"
run apply --dry-run; rc=$?
assert_eq "dry-run: код 0" 0 "$rc"
assert_eq "dry-run: без записи" 0 "$(sets)"
assert_eq "dry-run: без копий" 0 "$(nbackups)"
run apply
assert_eq "mru-sources: RU первая" "[('xkb', 'ru'), ('xkb', 'us')]" "$(gsv $IS mru-sources)"
teardown

echo "== apply: старый Cinnamon (libgnomekbd)"
setup
mk $KBD layouts "['us', 'ru']"
mk $KBD options "['grp\\tgrp:win_space_toggle']"
mk $KBDD default-group "1"
mk $KBDD group-per-window "true"
run apply; rc=$?
assert_eq "код 0" 0 "$rc"
assert_eq "layouts: RU первая" "['ru', 'us']" "$(gsv $KBD layouts)"
assert_eq "default-group = 0" "0" "$(gsv $KBDD default-group)"
assert_eq "options не тронуты" "['grp\\tgrp:win_space_toggle']" "$(gsv $KBD options)"
assert_eq "group-per-window не тронут" "true" "$(gsv $KBDD group-per-window)"
teardown

echo "== Ошибки и защита"
setup
mk_cinnamon "something weird" "uint32 1"
run apply; rc=$?
assert_eq "неизвестный формат -> код 1" 1 "$rc"
assert_eq "неизвестный формат -> без записи" 0 "$(sets)"
teardown
setup
mk_cinnamon "[('xkb', 'us'), ('xkb', 'ru')]" "uint32 1"
touch "$MOCK_GS_DIR/$IS/.ro-sources"
run apply; rc=$?
assert_eq "заблокированный ключ -> код 1" 1 "$rc"
assert_eq "заблокированный ключ не изменён" "[('xkb', 'us'), ('xkb', 'ru')]" "$(gsv $IS sources)"
teardown
setup
mk org.example.other key "1"
run apply; rc=$?
assert_eq "нет схем раскладок -> код 2" 2 "$rc"
teardown
setup
export CLDC_GSETTINGS=/nonexistent/gsettings
run apply; rc=$?
assert_eq "нет gsettings -> код 1" 1 "$rc"
run status; rc=$?
assert_eq "нет gsettings: status -> 2" 2 "$rc"
teardown

echo "== apply --login"
setup
mk_cinnamon "[('xkb', 'us'), ('xkb', 'ru')]" "uint32 1"
XDG_CURRENT_DESKTOP=GNOME run apply --login; rc=$?
assert_eq "не Cinnamon: код 0" 0 "$rc"
assert_eq "не Cinnamon: без записи" 0 "$(sets)"
run apply --login; rc=$?
assert_eq "Cinnamon: код 0" 0 "$rc"
assert_eq "Cinnamon: RU первая" "[('xkb', 'ru'), ('xkb', 'us')]" "$(gsv $IS sources)"
assert_eq "Cinnamon: тихий режим" "" "$(cat "$T/out")"
assert_true "журнал пишется" test -s "$HOME/.local/state/cldc-russian-default/cldc-russian-default.log"
teardown

echo "== install / status / restore / uninstall"
setup
mk_cinnamon "[('xkb', 'us'), ('xkb', 'de'), ('xkb', 'ru')]" "uint32 2"
run install; rc=$?
desk="$HOME/.config/autostart/cldc-russian-default.desktop"
bin="$HOME/.local/bin/cldc-russian-default"
assert_eq "install: код 0" 0 "$rc"
assert_true "install: скрипт скопирован" cmp -s "$SCRIPT" "$bin"
assert_true "install: автозапуск создан" test -f "$desk"
assert_true "install: Exec с --login" grep -qF "Exec=bash \"$bin\" apply --login" "$desk"
assert_eq "install: применено" "[('xkb', 'ru'), ('xkb', 'us'), ('xkb', 'de')]" "$(gsv $IS sources)"
cp "$desk" "$T/desk1"
before=$(sets)
run install; rc=$?
assert_eq "повторный install: код 0" 0 "$rc"
assert_true "повторный install: тот же .desktop" cmp -s "$T/desk1" "$desk"
assert_eq "повторный install: без записи" "$before" "$(sets)"
bash "$bin" install >"$T/out" 2>&1; rc=$?
assert_eq "install из установленной копии: код 0" 0 "$rc"
run status; rc=$?
assert_eq "status: код 0" 0 "$rc"
assert_true "status: показывает current" grep -q 'current: *uint32 0' "$T/out"
mk $IS current "uint32 1"
run status; rc=$?
assert_eq "status: ручное переключение -> код 0" 0 "$rc"
assert_true "status: сообщает о ручном переключении" grep -q 'переключено вручную' "$T/out"
run restore; rc=$?
assert_eq "restore: код 0" 0 "$rc"
assert_eq "restore: исходный sources" "[('xkb', 'us'), ('xkb', 'de'), ('xkb', 'ru')]" "$(gsv $IS sources)"
assert_eq "restore: исходный current" "uint32 2" "$(gsv $IS current)"
run restore latest
assert_eq "restore latest: отмена восстановления" "[('xkb', 'ru'), ('xkb', 'us'), ('xkb', 'de')]" "$(gsv $IS sources)"
printf 'org.evil\tkey\tvalue\n' >"$T/bad.tsv"
run restore "$T/bad.tsv"; rc=$?
assert_eq "restore: чужой файл отклонён" 1 "$rc"
run uninstall --restore; rc=$?
assert_eq "uninstall: код 0" 0 "$rc"
assert_false "uninstall: автозапуск удалён" test -e "$desk"
assert_false "uninstall: скрипт удалён" test -e "$bin"
assert_eq "uninstall --restore: исходный sources" "[('xkb', 'us'), ('xkb', 'de'), ('xkb', 'ru')]" "$(gsv $IS sources)"
assert_true "uninstall: копии сохранены" test -f "$HOME/.local/state/cldc-russian-default/backups/original.tsv"
run uninstall --purge; rc=$?
assert_eq "uninstall --purge: код 0" 0 "$rc"
assert_false "uninstall --purge: данные удалены" test -e "$HOME/.local/state/cldc-russian-default"
mkdir -p "${desk%/*}"; echo "[Desktop Entry]" >"$desk"
run uninstall
assert_true "uninstall: чужой файл не удалён" test -f "$desk"
teardown

echo
echo "Итого: $PASS пройдено, $FAIL с ошибками"
(( FAIL == 0 ))
