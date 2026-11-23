#!/usr/bin/env bash
# Leere Proxys (0 Byte) finden und dem Original zuordnen. Nur lesend.
#
# Hintergrund (Befund 11): Scheitert ffmpeg, hinterlässt v4 zentral und in Proxies/ eine
# leere Datei, die danach als fertig gilt. Neu erzeugen lässt sich ein Proxy aber nur,
# wenn das Original noch in Aufnahmen liegt. Liegt es nur noch auf Band oder ist es
# gelöscht, darf der leere Proxy nicht als „neu zu rechnen“ gelten.
#
# Ausgabe (Tabulator-getrennt), je leerem Proxy eine Zeile:
#   Gruppe   Proxy   Original
# Gruppen:
#   original_da     Original liegt in Aufnahmen; Proxy kann neu gerechnet werden
#   original_fehlt  kein Original in Aufnahmen (auf Band, verschoben oder gelöscht)
#   original_00     Original liegt in Aufnahmen/00_* oder 01_* (wird nicht gerechnet)
#
# Aufruf: bash leere_proxys.sh [<Aufnahmen>] [<zentrale Ablage>]

set -u
set -o pipefail

AUFNAHMEN="${1:-/mnt/Aufnahme_mirror/Aufnahmen}"
ZENTRAL="${2:-/mnt/Mirror_2x8TB/Proxy_Output/mnt/Aufnahmen}"

ist_videoendung() {
    local e="${1##*.}"
    [ "$e" != "$1" ] || return 1
    case "$(printf %s "$e" | tr "[:upper:]" "[:lower:]")" in
        mp4 | mxf | mov | mpeg | avi | mts) return 0 ;;
    esac
    return 1
}

gruppe_fuer() {
    local original="$1" rel erster
    if [ -z "$original" ]; then
        echo original_fehlt
        return
    fi
    rel="${original#"$AUFNAHMEN"/}"
    erster="${rel%%/*}"
    case "$erster" in
        00_* | 01_*) echo original_00 ;;
        *) echo original_da ;;
    esac
}

# Lokale Proxys: <Ordner>/Proxies/<Name>.mov gehört zu <Ordner>/<Name>.<Videoendung>
find "$AUFNAHMEN" -type f -path '*/Proxies/*' -name '*.mov' -size 0 -print0 2>/dev/null |
    while IFS= read -r -d '' proxy; do
        ordner="$(dirname -- "$(dirname -- "$proxy")")"
        stamm="$(basename -- "$proxy" .mov)"
        original=""
        for f in "$ordner"/*; do
            [ -f "$f" ] || continue
            n="$(basename -- "$f")"
            case "$n" in .*) continue ;; esac
            if [ "${n%.*}" = "$stamm" ] && ist_videoendung "$n"; then
                original="$f"
                break
            fi
        done
        printf '%s\t%s\t%s\n' "$(gruppe_fuer "$original")" "$proxy" "$original"
    done

# Zentrale Proxys: <ZENTRAL>/<Pfad>/<Name>.<ext>.mov gehört zu <Aufnahmen>/<Pfad>/<Name>.<ext>
find "$ZENTRAL" -type f -name '*.mov' -size 0 -print0 2>/dev/null |
    while IFS= read -r -d '' proxy; do
        rel="${proxy#"$ZENTRAL"/}"
        original="$AUFNAHMEN/${rel%.mov}"
        [ -f "$original" ] || original=""
        printf '%s\t%s\t%s\n' "$(gruppe_fuer "$original")" "$proxy" "$original"
    done
