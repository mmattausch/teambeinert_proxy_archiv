#!/usr/bin/bash
# Phase 0, lange Abfragen auf ELSA (Proxy-Skript v5 und Archivskript).
# Nur lesend. Schreibt ausschließlich nach /tmp/phase0.
# Start: systemd-run --unit=phase0-lang /usr/bin/bash /tmp/phase0_lang.sh
# Fortschritt: cat /tmp/phase0/lang_status.txt
#
# Hinweis: Die TSV-Listen trennen mit Tabulator. Dateinamen mit Tabulator oder
# Zeilenumbruch werden darin falsch dargestellt; für die Zählungen reicht das.

set -u

AUF=/mnt/Aufnahme_mirror/Aufnahmen
OUT=/tmp/phase0
mkdir -p "$OUT"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
status() { echo "$(ts) $*" >> "$OUT/lang_status.txt"; }

: > "$OUT/lang_status.txt"
status "Start"

IMG=$(docker image inspect linuxserver/ffmpeg --format '{{.Id}}' 2>/dev/null)
if [ -z "$IMG" ]; then
    status "FEHLER: Image linuxserver/ffmpeg lokal nicht vorhanden, Abbruch (kein Pull)."
    exit 2
fi
status "Image: $IMG"

# 1. Alle Videodateien wie in v4 (Endungen, ohne versteckte Dateien)
status "1/6 Dateiliste"
find "$AUF" -type f ! -name '.*' \
    \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) \
    -printf '%p\t%s\t%TY-%Tm-%Td\n' > "$OUT/videodateien_alle.tsv"

# Ohne Aufnahmen/00_*, Aufnahmen/01_* (erster Ordner) und ohne Proxies/
grep -v -E "^${AUF}/0[01]_[^/]*/" "$OUT/videodateien_alle.tsv" \
    | grep -v '/Proxies/' > "$OUT/videodateien.tsv"

# 2. Verteilung nach Endung: Anzahl und Größe
status "2/6 Endungen"
awk -F'\t' '{
    n = split($1, a, "."); e = tolower(a[n]); c[e]++; s[e] += $2
} END {
    for (e in c) printf "%s\t%d Dateien\t%.1f GB\n", e, c[e], s[e] / 1e9
}' "$OUT/videodateien.tsv" | sort > "$OUT/endungen.txt"
wc -l < "$OUT/videodateien.tsv" > "$OUT/anzahl_videodateien.txt"

# 3. Dateien direkt im Wurzelordner Aufnahmen; gleiche Namen mit verschiedenen Videoendungen
status "3/6 Wurzelordner und Namenspaare"
find "$AUF" -maxdepth 1 -type f > "$OUT/wurzel_dateien.txt"
awk -F'\t' '{
    p = $1; d = p; sub(/\/[^\/]*$/, "", d)
    f = substr(p, length(d) + 2); b = f; sub(/\.[^.]*$/, "", b)
    k = d "/" tolower(b); n[k]++; l[k] = l[k] "  |  " f
} END {
    for (k in n) if (n[k] > 1) print n[k] "\t" k "\t" l[k]
}' "$OUT/videodateien.tsv" | sort > "$OUT/namenspaare.txt"

# 4. Platz der Proxies-Ordner in Aufnahme_mirror
status "4/6 Platz Proxies"
find "$AUF" -type d -name Proxies -prune -print0 \
    | du -sc --block-size=1G --files0-from=- | tail -1 > "$OUT/proxies_platz.txt"

# 5. Umfang des Bestands in h264_archiv
status "5/6 h264_archiv"
H="$AUF/00_to_Backup/h264_archiv"
if [ -d "$H" ]; then
    find "$H" -type f -printf '%s\n' \
        | awk '{n++; s += $1} END {printf "%d Dateien, %.1f GB\n", n, s / 1e9}' > "$OUT/h264_archiv_umfang.txt"
else
    echo "Ordner nicht vorhanden: $H" > "$OUT/h264_archiv_umfang.txt"
fi

# 6. ffprobe-Stichprobe über 100 zufällige Videodateien (Container nur lesend)
status "6/6 Stichprobe ffprobe"
shuf -n 100 "$OUT/videodateien.tsv" | cut -f1 > "$OUT/stichprobe_liste.txt"
: > "$OUT/stichprobe_ffprobe.txt"
while IFS= read -r -u 3 f; do
    printf '=== %s\n' "$f" >> "$OUT/stichprobe_ffprobe.txt"
    docker run --rm --pull never -v "$AUF:$AUF:ro" --entrypoint ffprobe "$IMG" \
        -v error \
        -show_entries 'format=format_name,duration:format_tags=timecode:stream=index,codec_type,codec_name,profile,width,height,pix_fmt,field_order,r_frame_rate,channels,channel_layout:stream_tags=timecode' \
        -of compact "$f" < /dev/null >> "$OUT/stichprobe_ffprobe.txt" 2>&1
    tc=$(docker run --rm --pull never -v "$AUF:$AUF:ro" "$IMG" -hide_banner -nostdin -i "$f" < /dev/null 2>&1 \
        | grep -Eo 'timecode\s*:\s*[0-9]{2}:[0-9]{2}:[0-9]{2}[;:][0-9]{2}' | awk '{print $NF}' | head -n 1)
    printf 'Timecode wie v4: %s\n' "${tc:-keiner}" >> "$OUT/stichprobe_ffprobe.txt"
done 3< "$OUT/stichprobe_liste.txt"

status "Ende"
