#!/usr/bin/env bash
#
# Copy UF2 firmware onto boards as their bootloader volumes appear.
#
# Waits for any volume with an INFO_UF2.TXT at its root, so it works for
# anything using a UF2 bootloader, not just the nice!nano's NICENANO. Handles
# one file at a time and waits for the board to reboot before moving on, so a
# split keyboard's two halves can't be flashed with the same image by accident.
#
# Usage: flash-uf2.sh <firmware.uf2>...
#
# Env:
#   UF2_VOLUMES   glob for candidate mount points (default: /Volumes/*)
#   UF2_TIMEOUT   seconds to wait for a bootloader volume (default: 120)
#   UF2_BACKUP    set to 0 to skip saving the board's existing firmware
#   UF2_BACKUP_DIR  where backups go (default: firmware/backup)

set -euo pipefail

glob="${UF2_VOLUMES:-/Volumes/*}"
timeout="${UF2_TIMEOUT:-120}"
backup_dir="${UF2_BACKUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/firmware/backup}"

bold=$'\033[1m'; red=$'\033[31m'; green=$'\033[32m'; dim=$'\033[2m'; off=$'\033[0m'

die()  { printf '%s%s%s\n' "$red" "$*" "$off" >&2; exit 1; }
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s%s%s\n' "$bold" "$*" "$off"; }

find_volume() {
    local v
    for v in $glob; do
        if [[ -f "$v/INFO_UF2.TXT" ]]; then printf '%s\n' "$v"; return 0; fi
    done
    return 1
}

[[ $# -gt 0 ]] || die "usage: flash-uf2.sh <firmware.uf2>..."
for uf2 in "$@"; do
    [[ -f "$uf2" ]] || die "no such file: $uf2"
done

say "${dim}Watching $glob for a UF2 bootloader (INFO_UF2.TXT)${off}"

for uf2 in "$@"; do
    name=$(basename "$uf2")
    case "$name" in
        *_left*)  side=" — LEFT half" ;;
        *_right*) side=" — RIGHT half" ;;
        *)        side="" ;;
    esac

    step "$name$side  ($(wc -c <"$uf2" | tr -d ' ') bytes)"

    if vol=$(find_volume); then
        say "  bootloader already mounted at $vol"
    else
        say "  put the board into its bootloader: double-tap reset, or short RST to GND twice"
        printf '  waiting'
        vol=""
        for (( i = 0; i < timeout * 2; i++ )); do
            if vol=$(find_volume); then break; fi
            vol=""
            (( i % 4 == 0 )) && printf '.'
            sleep 0.5
        done
        printf '\n'
        [[ -n "$vol" ]] || die "  timed out after ${timeout}s with no bootloader volume"
        say "  found $vol"
    fi

    # Tells you which board you actually caught, which matters when two halves
    # are plugged in and only one is in its bootloader.
    sed -n 's/^Model: */  model:   /p; s/^Board-ID: */  boardid: /p' \
        "$vol/INFO_UF2.TXT" 2>/dev/null || true

    # Most UF2 bootloaders (including the nice!nano's) expose the firmware
    # currently on the board as CURRENT.UF2. Grab it before overwriting --
    # it is the only copy of whatever is already flashed.
    if [[ "${UF2_BACKUP:-1}" != "0" && -f "$vol/CURRENT.UF2" ]]; then
        mkdir -p "$backup_dir"
        dest="$backup_dir/$(date +%Y%m%dT%H%M%S)-before-${name}"
        if cp "$vol/CURRENT.UF2" "$dest" 2>/dev/null; then
            say "  ${green}backed up existing firmware${off} -> $dest"
        else
            say "  ${red}could not read CURRENT.UF2 — no backup taken${off}"
        fi
    else
        [[ "${UF2_BACKUP:-1}" == "0" ]] || say "  ${dim}no CURRENT.UF2 on $vol; nothing to back up${off}"
    fi

    say "  copying $name -> $vol/"
    # The board reboots the moment the write completes, so the volume can
    # vanish mid-copy and cp reports an error. Disappearance is the success
    # signal, checked below.
    cp "$uf2" "$vol/" 2>/dev/null || true

    printf '  waiting for reboot'
    for (( i = 0; i < 60; i++ )); do
        [[ -d "$vol" ]] || break
        (( i % 4 == 0 )) && printf '.'
        sleep 0.5
    done
    printf '\n'
    [[ -d "$vol" ]] && die "  $vol never unmounted — the copy probably failed"

    say "  ${green}flashed${off}"
done

step "All done."
