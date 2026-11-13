#!/usr/bin/env bash
# Erzeugt kurze Testdateien für Proxy-Skript v5 und Archivskript.
#
# Deckt die Fälle ab, die der Testkorpus Aufnahmen/2025-03-04_PROXY nicht hat:
# bösartige und schwierige Dateinamen, Tonaufbauten, Timecode-Varianten,
# Datei ohne Video, defekte Datei, Ausschlussordner.
#
# Aufruf:  tests/erzeuge_testdateien.sh <Zielordner>
#          Legt darunter einen Baum "Aufnahmen/…" an. Der Zielordner muss leer sein
#          oder noch nicht existieren. Es wird nur dort geschrieben.
#
# Braucht Docker. Nutzt dasselbe Image wie die Skripte (FFMPEG_IMAGE, Standard: der
# festgeschriebene Digest). Auf einem arm64-Mac lädt Docker die arm64-Fassung; für das
# Erzeugen von Testdateien ist das gleichgültig.

set -u
set -o pipefail

FFMPEG_IMAGE="${FFMPEG_IMAGE:-linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697}"
DAUER=2

if [ $# -ne 1 ]; then
    echo "Aufruf: $0 <Zielordner>" >&2
    exit 2
fi

ziel_basis="$1"
if [ -e "$ziel_basis" ] && [ -n "$(ls -A "$ziel_basis" 2>/dev/null)" ]; then
    echo "Zielordner ist nicht leer: $ziel_basis" >&2
    exit 2
fi
mkdir -p "$ziel_basis"
ziel_basis="$(cd "$ziel_basis" && pwd)"
auf="$ziel_basis/Aufnahmen"
kamera="$auf/2026-01-01_Testprojekt/Kamera"
mkdir -p "$kamera/Proxies" "$auf/00_to_Backup/AUF999/2025-01-01_Alt" "$auf/01_zum_Band/AUF998/2025-01-02_Alt" "$auf/2026-01-02_Telefon"

fehler=0

# Vorab prüfen, ob Docker diesen Ordner wirklich einbindet. Colima und Docker Desktop
# teilen auf dem Mac nur bestimmte Ordner (meist nur das Benutzerverzeichnis); sonst
# landen die Dateien unbemerkt in der virtuellen Maschine.
probe=".einbindung_$$"
docker run --rm -v "$auf:/ziel" --entrypoint touch "$FFMPEG_IMAGE" "/ziel/$probe" < /dev/null
if [ ! -e "$auf/$probe" ]; then
    echo "Docker sieht den Ordner $auf nicht (nicht freigegeben)." >&2
    echo "Einen Ordner unterhalb des Benutzerverzeichnisses nehmen, z. B. tests/daten im Repository." >&2
    exit 2
fi
rm -f "$auf/$probe"

# ffmpeg im Container; Ausgabeordner als /ziel eingebunden.
# $1 = Zielpfad relativ zu $auf, Rest = ffmpeg-Argumente vor der Ausgabe.
erzeuge() {
    local rel="$1"; shift
    local -a cmd=(docker run --rm -v "$auf:/ziel" "$FFMPEG_IMAGE"
        -nostdin -hide_banner -loglevel error -y "$@" "file:/ziel/$rel")
    if "${cmd[@]}" < /dev/null; then
        printf 'ok      %s\n' "$rel"
    else
        printf 'FEHLER  %s\n' "$rel"
        fehler=$((fehler + 1))
    fi
}

# Bausteine
video=(-f lavfi -i "testsrc2=size=640x360:rate=25:duration=$DAUER")
sinus() { printf 'sin(%d*2*PI*t)' "$((300 + 50 * $1))"; }
# Eine Tonspur mit n Kanälen
ton_n() {
    local n="$1" i ausdruck=""
    for ((i = 0; i < n; i++)); do
        ausdruck+="${ausdruck:+|}$(sinus "$i")"
    done
    printf 'aevalsrc=exprs=%s:s=48000:d=%s' "$ausdruck" "$DAUER"
}
h264=(-c:v libx264 -preset ultrafast -pix_fmt yuv420p)
aac=(-c:a aac)
pcm=(-c:a pcm_s24le)

k="2026-01-01_Testprojekt/Kamera"

echo "== Namen"
erzeuge "$k/normal.mp4"                     "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/mit Leerzeichen.mp4"            "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/Umlaute_äöüß_ÄÖÜ.mp4"           "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/clip\$(cd;touch proxy_v5_pwned).mp4" "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/clip\`cd;touch proxy_v5_pwned2\`.mp4" "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/Anführung \"doppelt\" und 'einfach'.mp4" "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/Semikolon; und & und [Klammern].mp4" "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/Doppel:punkt.mp4"               "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/-beginnt_mit_minus.mp4"         "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/$(printf 'langer_name_%.0s' {1..18})ende.mp4" "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/GROSS_ENDUNG.MP4"               "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/Backslash\\im_Namen.mp4"        "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
# Zeilenumbruch im Namen: erst normal erzeugen, dann umbenennen
erzeuge "$k/zeilenumbruch_tmp.mp4"          "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
mv "$auf/$k/zeilenumbruch_tmp.mp4" "$auf/$k/Zeilen"$'\n'"umbruch.mp4"

echo "== Ton"
erzeuge "$k/ton_ohne.mp4"                   "${video[@]}" "${h264[@]}"
erzeuge "$k/ton_1kanal.mov"                 "${video[@]}" -f lavfi -i "$(ton_n 1)" "${h264[@]}" "${pcm[@]}" -shortest
for n in 3 4 5 6 7 8 16; do
    erzeuge "$k/ton_${n}kanal.mov"          "${video[@]}" -f lavfi -i "$(ton_n "$n")" "${h264[@]}" "${pcm[@]}" -shortest
done
erzeuge "$k/ton_4x_mono.mov"                "${video[@]}" \
    -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" \
    -map 0:v -map 1:a -map 2:a -map 3:a -map 4:a "${h264[@]}" "${pcm[@]}" -shortest
erzeuge "$k/ton_2x_stereo.mov"              "${video[@]}" -f lavfi -i "$(ton_n 2)" -f lavfi -i "$(ton_n 2)" \
    -map 0:v -map 1:a -map 2:a "${h264[@]}" "${pcm[@]}" -shortest
erzeuge "$k/ton_gemischt_2_und_16.mov"      "${video[@]}" -f lavfi -i "$(ton_n 2)" -f lavfi -i "$(ton_n 16)" \
    -map 0:v -map 1:a -map 2:a "${h264[@]}" "${pcm[@]}" -shortest
erzeuge "$k/ton_gemischt_16_und_2.mov"      "${video[@]}" -f lavfi -i "$(ton_n 16)" -f lavfi -i "$(ton_n 2)" \
    -map 0:v -map 1:a -map 2:a "${h264[@]}" "${pcm[@]}" -shortest
erzeuge "$k/ton_2x_16kanal.mov"             "${video[@]}" -f lavfi -i "$(ton_n 16)" -f lavfi -i "$(ton_n 16)" \
    -map 0:v -map 1:a -map 2:a "${h264[@]}" "${pcm[@]}" -shortest
erzeuge "$k/nur_ton_kein_video.mov"         -f lavfi -i "$(ton_n 2)" "${pcm[@]}"

echo "== Timecode"
erzeuge "$k/tc_ohne.mov"                    "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/tc_25p.mov"                     "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest -timecode 10:00:00:00
erzeuge "$k/tc_2997_dropframe.mov"          -f lavfi -i "testsrc2=size=640x360:rate=30000/1001:duration=$DAUER" \
    -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest -timecode "01:00:00;00"

echo "== Bild"
erzeuge "$k/zwei_videospuren.mp4"           "${video[@]}" -f lavfi -i "testsrc=size=320x176:rate=25:duration=$DAUER" \
    -f lavfi -i "$(ton_n 1)" -map 0:v -map 1:v -map 2:a "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/ungerade_breite_1918x1080.mov"  -f lavfi -i "testsrc2=size=1918x1080:rate=25:duration=$DAUER" \
    -f lavfi -i "$(ton_n 2)" -c:v libx264 -preset ultrafast -pix_fmt yuv444p "${aac[@]}" -shortest
erzeuge "$k/hochformat_1080x1920.mp4"       -f lavfi -i "testsrc2=size=1080x1920:rate=25:duration=$DAUER" \
    -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "$k/zehnbit_422.mov"                "${video[@]}" -f lavfi -i "$(ton_n 2)" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv422p10le "${pcm[@]}" -shortest
erzeuge "$k/mxf_8x_mono.mxf"                -f lavfi -i "testsrc2=size=1920x1080:rate=25:duration=$DAUER" \
    -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" \
    -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" -f lavfi -i "$(ton_n 1)" \
    -map 0:v -map 1:a -map 2:a -map 3:a -map 4:a -map 5:a -map 6:a -map 7:a -map 8:a \
    -c:v mpeg2video -pix_fmt yuv422p -b:v 20M -c:a pcm_s24le -shortest -f mxf
erzeuge "$k/avchd.mts"                      "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" -c:a ac3 -shortest -f mpegts

echo "== Defekt"
erzeuge "$k/defekt_abgeschnitten.mp4"       -f lavfi -i "testsrc2=size=640x360:rate=25:duration=6" \
    -f lavfi -i "aevalsrc=exprs=sin(440*2*PI*t):s=48000:d=6" "${h264[@]}" "${aac[@]}" -shortest
datei="$auf/$k/defekt_abgeschnitten.mp4"
groesse=$(wc -c < "$datei")
head -c $((groesse / 2)) "$datei" > "$datei.halb" && mv "$datei.halb" "$datei"
printf 'ok      %s (auf %d Byte gekürzt)\n' "$k/defekt_abgeschnitten.mp4" $((groesse / 2))
printf 'kein Video, nur Text\n' > "$auf/$k/kein_video_nur_text.mp4"
printf 'ok      %s\n' "$k/kein_video_nur_text.mp4"

echo "== Auswahl und Ausschlüsse"
erzeuge "$k/.versteckt.mp4"                 "${video[@]}" "${h264[@]}"
erzeuge "$k/Proxies/alter_proxy.mov"        "${video[@]}" "${h264[@]}"
erzeuge "00_to_Backup/AUF999/2025-01-01_Alt/im_sammelordner.mp4" "${video[@]}" "${h264[@]}"
erzeuge "01_zum_Band/AUF998/2025-01-02_Alt/im_bandordner.mp4"    "${video[@]}" "${h264[@]}"
erzeuge "2026-01-02_Telefon/VID_20260102_120000_00_001.mp4"       "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "2026-01-02_Telefon/Tag_100_Bühne.mov"                    "${video[@]}" -f lavfi -i "$(ton_n 2)" "${h264[@]}" "${aac[@]}" -shortest
erzeuge "2026-01-02_Telefon/keine_videoendung.mkv"                "${video[@]}" "${h264[@]}"
erzeuge "im_wurzelordner.mp4"                                     "${video[@]}" "${h264[@]}"

echo
if [ "$fehler" -eq 0 ]; then
    echo "Fertig: alle Testdateien erzeugt unter $auf"
else
    echo "Fertig mit $fehler Fehlern, siehe oben."
fi
for f in "$HOME/proxy_v5_pwned" "$HOME/proxy_v5_pwned2"; do
    if [ -e "$f" ]; then
        echo "WARNUNG: $f existiert. Ein Dateiname wurde als Befehl ausgeführt." >&2
        fehler=$((fehler + 1))
    fi
done
[ "$fehler" -eq 0 ]
