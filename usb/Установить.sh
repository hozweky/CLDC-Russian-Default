#!/usr/bin/env bash
# Резервный установщик: если ярлык «Установить» не запускается.
# В терминале: bash Установить.sh   (или: bash app/usb-launcher.sh install)
DIR=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)
exec bash "$DIR/app/usb-launcher.sh" install "$@"
