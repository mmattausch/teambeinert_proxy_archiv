#!/usr/bin/bash
# Phase 0: Testordner Aufnahmen/2025-03-04_PROXY untersuchen.
# Nur lesend. Schreibt ausschließlich nach /tmp/phase0/korpus_ffprobe.txt.
# Je Originaldatei: Spuren und Laufzeit von Original, lokalem Proxy und zentralem Proxy,
# dazu Größe und Änderungszeit der Proxys.
# Start: systemd-run --unit=phase0-korpus /usr/bin/bash /tmp/korpus_ffprobe.sh
# Fortschritt: tail -3 /tmp/phase0/korpus_ffprobe.txt

set -u

AUF=/mnt/Aufnahme_mirror/Aufnahmen
KORPUS="$AUF/2025-03-04_PROXY"

OUT=/tmp/phase0/korpus_ffprobe.txt
mkdir -p /tmp/phase0

IMG=$(docker image inspect linuxserver/ffmpeg --format '{{.Id}}' 2>/dev/null)
if [ -z "$IMG" ]; then
    echo "FEHLER: Image linuxserver/ffmpeg lokal nicht vorhanden, Abbruch (kein Pull)." > "$OUT"
    exit 2
fi

probe() {
    docker run --rm --pull never \
        -v "$AUF:$AUF:ro" \
        -v /mnt/Mirror_2x8TB/Proxy_Output:/mnt/Mirror_2x8TB/Proxy_Output:ro \
        --entrypoint ffprobe "$IMG" -v error \
        -show_entries 'format=format_name,duration,bit_rate:format_tags=timecode:stream=index,codec_type,codec_name,profile,level,width,height,pix_fmt,field_order,r_frame_rate,channels:stream_tags=timecode' \
        -of compact "$1" < /dev/null 2>&1
}

zeile() {
    if [ -f "$1" ]; then
        stat -c 'Datei: %s Byte, geändert %y' "$1"
        probe "$1"
    else
        echo "fehlt: $1"
    fi
}

{
    echo "Stand: $(date '+%Y-%m-%d %H:%M:%S'), Image $IMG"
    find "$KORPUS" -type f ! -name '.*' ! -path '*/Proxies/*' \
        \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) \
        -print0 | sort -z | while IFS= read -r -d '' f; do
        rel="${f#$AUF/}"
        dir="${f%/*}"
        base="${f##*/}"
        echo "################ $rel"
        echo "--- Original"
        zeile "$f"
        echo "--- Proxy lokal"
        zeile "$dir/Proxies/${base%.*}.mov"
        echo "--- Proxy zentral"
        zeile "/mnt/Mirror_2x8TB/Proxy_Output/mnt/Aufnahmen/$rel.mov"
    done
    echo "Ende: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$OUT" 2>&1
