#!/usr/bin/env bash
# CLDC-Russian-Default, USB-версия: установка и проверка двойным щелчком.
# Вызывается из ярлыков «Установить» / «Проверить установку» или вручную:
#   bash app/usb-launcher.sh install
#   bash app/usb-launcher.sh check
# Работает из любой папки, без root/sudo, паролей и интернета.
# Права на исполнение не нужны: все файлы запускаются через bash.

set -uo pipefail

MODE=${1:-install}
SELF=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")
APP_DIR=$(cd -- "$(dirname -- "$SELF")" && pwd)
TOOL="$APP_DIR/cldc-russian-default"
INSTALLED="$HOME/.local/bin/cldc-russian-default"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/cldc-russian-default.desktop"
REPORT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cldc-russian-default"
REPORT="$REPORT_DIR/usb-$MODE-report.txt"
SUMMARY=""

in_terminal() { [[ -t 0 && -t 1 ]]; }

if in_terminal; then
  C_OK=$'\e[1;32m' C_ERR=$'\e[1;31m' C_WARN=$'\e[1;33m' C_OFF=$'\e[0m'
else
  C_OK="" C_ERR="" C_WARN="" C_OFF=""
fi

out() { printf '%s\n' "$*"; printf '%s\n' "$*" >>"$REPORT" 2>/dev/null; }
line() { out "================================================================"; }
ok_box() {
  SUMMARY=$1
  out ""; printf '%s' "$C_OK"; line; shift
  out "  $SUMMARY"; local s; for s in "$@"; do out "  $s"; done
  line; printf '%s' "$C_OFF"
}
err_box() {
  SUMMARY=$1
  out ""; printf '%s' "$C_ERR"; line; shift
  out "  $SUMMARY"; local s; for s in "$@"; do out "  $s"; done
  line; printf '%s' "$C_OFF"
}
warn_line() { printf '%s' "$C_WARN"; out "ВНИМАНИЕ: $*"; printf '%s' "$C_OFF"; }

# Запуск команды с выводом и на экран, и в отчёт. Возвращает код команды.
run_logged() {
  "$@" 2>&1 | tee -a "$REPORT"
  return "${PIPESTATUS[0]}"
}

# --------------------------------------------------------------- проверки

preflight() {
  if [[ ${CLDC_USB_SKIP_OS_CHECK:-0} != 1 && $(uname -s) != Linux ]]; then
    err_box "ОШИБКА: эта программа запускается только на ноутбуке с Linux."
    return 1
  fi
  if (( EUID == 0 )) && [[ ${CLDC_ALLOW_ROOT:-0} != 1 ]]; then
    err_box "ОШИБКА: запущено от имени root (администратора)." \
      "Войдите в систему пользователем guest и запустите «$( [[ $MODE == check ]] && echo 'Проверить установку' || echo 'Установить')» снова." \
      "Пароль и sudo не нужны."
    return 1
  fi
  if [[ ! -f $TOOL ]]; then
    err_box "ОШИБКА: не найден файл программы:" "$TOOL" \
      "Скопируйте папку CLDC-Russian-Default-USB целиком, вместе с папкой app."
    return 1
  fi
  if [[ ! -w $HOME ]]; then
    err_box "ОШИБКА: нет доступа на запись в домашнюю папку $HOME."
    return 1
  fi
  return 0
}

# Если файл программы испортили переводы строк Windows (CRLF) — чиним во временной копии.
prepare_tool() {
  if [[ -n $(tr -cd '\r' <"$TOOL" 2>/dev/null) ]]; then
    local tmp
    tmp=$(mktemp -d 2>/dev/null) || { printf '%s' "$TOOL"; return; }
    tr -d '\r' <"$TOOL" >"$tmp/cldc-russian-default"
    warn_line "файл программы был с переводами строк Windows — использую исправленную копию." >&2
    printf '%s' "$tmp/cldc-russian-default"
  else
    printf '%s' "$TOOL"
  fi
}

session_notes() {
  local user
  user=$(id -un 2>/dev/null || printf '%s' "${USER:-?}")
  out "Пользователь: $user"
  out "Папка:        ${APP_DIR%/app}"
  [[ $user == guest ]] || warn_line "вы вошли как «$user», а не guest. Установка будет выполнена для «$user»."
  local d="${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}"
  [[ ${d,,} == *cinnamon* ]] || warn_line "рабочий стол не похож на Cinnamon (${XDG_CURRENT_DESKTOP:-неизвестно})."
}

# --------------------------------------------------------------- режимы

do_install() {
  out "CLDC-Russian-Default — установка русской раскладки по умолчанию"
  line
  session_notes
  preflight || return 1
  local tool rc
  tool=$(prepare_tool)

  out ""
  out "Шаг 1 из 2. Установка (без пароля, только для текущего пользователя)..."
  run_logged bash "$tool" install
  rc=$?
  if (( rc != 0 )); then
    err_box "ОШИБКА: установка не выполнена (код $rc)." \
      "Сообщения выше объясняют причину." \
      "Отчёт сохранён: $REPORT"
    return 1
  fi

  out ""
  out "Шаг 2 из 2. Проверка..."
  run_logged bash "$INSTALLED" status
  rc=$?
  case $rc in
    0)
      ok_box "ГОТОВО! Установка выполнена успешно." \
        "Русская раскладка (RU) будет включаться при каждом входе." \
        "Английская (US) — второй, переключение: Super+Пробел." \
        "" \
        "Теперь перезагрузите ноутбук." \
        "После входа можно открыть «Проверить установку»."
      return 0 ;;
    2)
      ok_box "Установлено, но проверить настройки сейчас не удалось." \
        "Перезагрузите ноутбук, войдите как guest и откройте «Проверить установку»."
      return 0 ;;
    *)
      err_box "ОШИБКА: установка выполнена, но проверка показала проблему (код $rc)." \
        "Смотрите строку «Итог» выше." \
        "Отчёт сохранён: $REPORT"
      return 1 ;;
  esac
}

do_check() {
  out "CLDC-Russian-Default — проверка установки"
  line
  session_notes
  preflight || return 1
  local tool rc
  if [[ -f $INSTALLED ]]; then tool=$INSTALLED; else tool=$(prepare_tool); fi
  out ""
  run_logged bash "$tool" status
  rc=$?
  if (( rc == 0 )); then
    ok_box "ВСЁ В ПОРЯДКЕ: русская раскладка включается по умолчанию." \
      "Английская (US) — второй, переключение: Super+Пробел."
    return 0
  fi
  if [[ ! -f $AUTOSTART ]]; then
    err_box "НЕ УСТАНОВЛЕНО: автозапуск не найден." \
      "Откройте «Установить»." \
      "Если вы уже устанавливали и это сообщение появилось после перезагрузки," \
      "профиль guest очищается при выходе — обратитесь к администратору."
  elif (( rc == 2 )); then
    err_box "Проверка невозможна: настройки Cinnamon сейчас недоступны." \
      "Запустите проверку из обычного сеанса Cinnamon пользователя guest."
  else
    err_box "ЕСТЬ ПРОБЛЕМА: русская раскладка не первая." \
      "Откройте «Установить» ещё раз или перезагрузите ноутбук." \
      "Отчёт сохранён: $REPORT"
  fi
  return 1
}

run_mode() {
  mkdir -p "$REPORT_DIR" 2>/dev/null
  : >"$REPORT" 2>/dev/null
  case $MODE in
    install) do_install ;;
    check) do_check ;;
    *) err_box "Неизвестный режим: $MODE (нужно install или check)."; return 2 ;;
  esac
}

pause() {
  [[ ${CLDC_USB_NO_PAUSE:-0} == 1 ]] && return 0
  in_terminal || return 0
  printf '\nНажмите Enter, чтобы закрыть это окно...'
  read -r _ || true
}

# --------------------------------------------------------------- окно терминала

terminal_candidates() {
  local t
  if [[ -n ${CLDC_USB_TERMINALS:-} ]]; then   # для тестов
    printf '%s\n' $CLDC_USB_TERMINALS
    return
  fi
  if command -v gsettings >/dev/null 2>&1; then
    t=$(gsettings get org.cinnamon.desktop.default-applications.terminal exec 2>/dev/null)
    t=${t//\'/}
    [[ -n $t ]] && printf '%s\n' "$t"
  fi
  printf '%s\n' gnome-terminal mate-terminal xfce4-terminal tilix konsole \
    lxterminal terminator alacritty kitty xterm x-terminal-emulator
}

# Открыть окно терминала и выполнить в нём этот же скрипт. 0 — окно запущено.
open_in_terminal() {
  local t pid st qcmd
  local -a cmd=(env CLDC_USB_IN_TERMINAL=1 bash "$SELF" "$MODE")
  qcmd=$(printf '%q ' "${cmd[@]}")
  while read -r t; do
    command -v "$t" >/dev/null 2>&1 || continue
    case ${t##*/} in
      gnome-terminal) set -- "$t" -- "${cmd[@]}" ;;
      mate-terminal | xfce4-terminal | terminator) set -- "$t" -x "${cmd[@]}" ;;
      tilix | lxterminal) set -- "$t" -e "$qcmd" ;;
      kitty) set -- "$t" "${cmd[@]}" ;;
      *) set -- "$t" -e "${cmd[@]}" ;;
    esac
    if command -v setsid >/dev/null 2>&1; then
      setsid "$@" >/dev/null 2>&1 </dev/null &
    else
      "$@" >/dev/null 2>&1 </dev/null &
    fi
    pid=$!
    sleep 2
    kill -0 "$pid" 2>/dev/null && return 0   # окно ещё открыто (xterm и т. п.)
    wait "$pid"; st=$?
    (( st == 0 )) && return 0                # gnome-terminal передал окно серверу
  done < <(terminal_candidates)
  return 1
}

# Терминал не найден: выполняем без окна и показываем отчёт доступным способом.
gui_fallback() {
  run_mode >/dev/null 2>&1
  local rc=$?
  if command -v zenity >/dev/null 2>&1; then
    zenity --text-info --title="CLDC-Russian-Default: $SUMMARY" \
      --filename="$REPORT" --width=760 --height=520 >/dev/null 2>&1
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "CLDC-Russian-Default" "$SUMMARY Отчёт: $REPORT"
    command -v xdg-open >/dev/null 2>&1 && xdg-open "$REPORT" >/dev/null 2>&1 &
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$REPORT" >/dev/null 2>&1 &
  fi
  return $rc
}

main() {
  if ! in_terminal && [[ ${CLDC_USB_IN_TERMINAL:-0} != 1 ]]; then
    open_in_terminal && return 0
    gui_fallback
    return $?
  fi
  run_mode
  local rc=$?
  pause
  return $rc
}

main; exit $?
