#!/usr/bin/env bash
# Ablauftests für archiv_h264.sh (neue Fassung), angelehnt an den Testplan der
# Änderungsliste, Abschnitt 7.
#
# Läuft in Linux mit Bash ≥ 4.4, GNU-Werkzeugen, flock und Docker (Colima-VM oder ELSA):
#   colima ssh -- bash -c 'cd <Repo> && tests/archiv_tests.sh'
#
# Legt tests/daten/ neu an. Ende mit 0, wenn alle Prüfungen bestanden sind.

set -u
set -o pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DATEN="$REPO/tests/daten"
AUF="$DATEN/Aufnahmen"
ZW="$AUF/00_to_Backup/h264_archiv"
PROT="$ZW/_protokolle"
KONF="$DATEN/archiv_test.konf"
K="2026-01-01_Testprojekt/Kamera"
SKRIPT="$REPO/archiv_h264.sh"
IMAGE="linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697"

bestanden=0
durchgefallen=0

pruefe() {
    local beschreibung="$1"; shift
    if "$@"; then
        printf '  ok    %s\n' "$beschreibung"
        bestanden=$((bestanden + 1))
    else
        printf '  FEHLT %s\n' "$beschreibung"
        durchgefallen=$((durchgefallen + 1))
    fi
}

archiv() { ARCHIV_KONF="$KONF" "$BASH" "$SKRIPT" "$@"; }
gleich() { [ "$1" = "$2" ]; }
datei_da() { [ -f "$1" ]; }
datei_fehlt() { [ ! -e "$1" ]; }
keine_teildateien() { [ -z "$(find "$DATEN" -name '*.teil' -print -quit)" ]; }

# letzte Protokollzeile zur Quelle: Feld 4 (ergebnis)
ergebnis_von() {
    local csv="$1" quelle="$2"
    python3 - "$csv" "$quelle" <<'EOF'
import csv, sys
erg = ""
with open(sys.argv[1], encoding="utf-8", newline="") as f:
    for zeile in csv.DictReader(f, delimiter=";"):
        if zeile["quelle"] == sys.argv[2]:
            erg = zeile["ergebnis"]
print(erg)
EOF
}

echo "== Vorbereitung"
rm -rf "$DATEN"
# Reste früherer Vergleichsläufe (das alte Archivskript führt Namen per eval aus)
rm -f "$HOME/proxy_v5_pwned" "$HOME/proxy_v5_pwned2"
"$REPO/tests/erzeuge_testdateien.sh" "$DATEN" > /dev/null || { echo "Testdateien konnten nicht erzeugt werden"; exit 2; }
cat > "$KONF" <<EOF
AUFNAHMEN="$AUF"
ZIEL_WURZEL="$ZW"
RESERVE_BYTE=\$((100 * 1024 * 1024))
EOF

AUFTRAG_DATEI="$DATEN/A0001.txt"
{
    echo "# Testauftrag"
    echo
    for n in normal.mp4 "mit Leerzeichen.mp4" "clip\$(cd;touch proxy_v5_pwned).mp4" "Anführung \"doppelt\" und 'einfach'.mp4" \
        ton_4x_mono.mov tc_2997_dropframe.mov zehnbit_422.mov mxf_8x_mono.mxf avchd.mts nur_ton_kein_video.mov \
        defekt_abgeschnitten.mp4 ton_16kanal.mov ton_3kanal.mov GROSS_ENDUNG.MP4; do
        echo "$AUF/$K/$n"
    done
    echo "$AUF/2026-01-02_Telefon/VID_20260102_120000_00_001.mp4"
    echo "$AUF/00_to_Backup/AUF999/2025-01-01_Alt/im_sammelordner.mp4"
    echo "$AUF/$K/gibt_es_nicht.mp4"
} > "$AUFTRAG_DATEI"
CSV="$PROT/A0001.csv"

echo "== 1. Auftrag"
archiv --auftrag "$AUFTRAG_DATEI" > "$DATEN/archiv1.txt" 2>&1
rc=$?
pruefe "Rückgabewert 1 (erwartete Fehler im Auftrag)" gleich "$rc" 1
pruefe "Protokoll A0001.csv angelegt" datei_da "$CSV"
pruefe "alle 17 Zeilen des Auftrags bearbeitet" gleich "$(python3 -c "import csv,sys;print(len(list(csv.DictReader(open(sys.argv[1],encoding='utf-8'),delimiter=';'))))" "$CSV")" 17
pruefe "kein Dateiname als Befehl ausgeführt" datei_fehlt "$HOME/proxy_v5_pwned"
pruefe "normal.mp4: ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/normal.mp4")" ok
pruefe "Ziel mit Originalendung im Namen" datei_da "$ZW/$K/normal.mp4.mov"
pruefe "Name mit \$(…): ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/clip\$(cd;touch proxy_v5_pwned).mp4")" ok
pruefe "Name mit Anführungszeichen: ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/Anführung \"doppelt\" und 'einfach'.mp4")" ok
pruefe "4× Mono: ok (Kanalsumme gleich)" gleich "$(ergebnis_von "$CSV" "$AUF/$K/ton_4x_mono.mov")" ok
pruefe "MXF 8× Mono: ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/mxf_8x_mono.mxf")" ok
pruefe "MTS: ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/avchd.mts")" ok
pruefe "Drop-Frame-Timecode: ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/tc_2997_dropframe.mov")" ok
pruefe "Datei ohne Video: kein_video" gleich "$(ergebnis_von "$CSV" "$AUF/$K/nur_ton_kein_video.mov")" kein_video
pruefe "defekte Datei: Fehler" gleich "$(ergebnis_von "$CSV" "$AUF/$K/defekt_abgeschnitten.mp4")" Fehler
pruefe "3 Kanäle: Fehler (v4-Zuordnung verdoppelt, Archiv prüft Kanalsumme)" gleich "$(ergebnis_von "$CSV" "$AUF/$K/ton_3kanal.mov")" Fehler
pruefe "Telefonvideo mit 00_ im Namen: ok (M7)" gleich "$(ergebnis_von "$CSV" "$AUF/2026-01-02_Telefon/VID_20260102_120000_00_001.mp4")" ok
pruefe "Datei in 00_to_Backup: uebersprungen" gleich "$(ergebnis_von "$CSV" "$AUF/00_to_Backup/AUF999/2025-01-01_Alt/im_sammelordner.mp4")" uebersprungen
pruefe "fehlende Datei: Fehler" gleich "$(ergebnis_von "$CSV" "$AUF/$K/gibt_es_nicht.mp4")" Fehler
pruefe "keine Archiv-Fassung für defekte Datei" datei_fehlt "$ZW/$K/defekt_abgeschnitten.mp4.mov"
pruefe "keine Teildateien übrig" keine_teildateien
pruefe "Zusammenfassung ausgegeben" grep -q "Zusammenfassung" "$DATEN/archiv1.txt"
pruefe "CSV: Kopfzeile wie M4" gleich "$(head -1 "$CSV")" "auftrag;quelle;ziel;ergebnis;meldung;groesse_quelle;groesse_ziel;laufzeit_quelle;laufzeit_ziel;aufloesung_quelle;aufloesung_ziel;videospuren_quelle;videospuren_ziel;tonkanaele_quelle;tonkanaele_ziel;timecode;beginn;ende;profil;ffmpeg_image;skript_version"
pruefe "CSV: ohne BOM" test "$(head -c 3 "$CSV" | od -An -tx1 | tr -d ' ')" != "efbbbf"
pruefe "CSV: Profilkennung" grep -q "archiv_h264_crf18_v1" "$CSV"

echo "== 2. Fortsetzen: zweiter Lauf rechnet nichts neu"
vorher="$(stat -c '%Y %s' "$ZW/$K/normal.mp4.mov")"
archiv --auftrag "$AUFTRAG_DATEI" > "$DATEN/archiv2.txt" 2>&1
pruefe "normal.mp4 jetzt vorhanden_ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/normal.mp4")" vorhanden_ok
pruefe "Archiv-Fassung unverändert" gleich "$(stat -c '%Y %s' "$ZW/$K/normal.mp4.mov")" "$vorher"
pruefe "Protokoll angehängt (Kopfzeile nur einmal)" gleich "$(grep -c '^auftrag;' "$CSV")" 1

echo "== 3. Vorhandene, kaputte Archiv-Fassung wird nicht übernommen"
z="$ZW/$K/GROSS_ENDUNG.MP4.mov"
head -c "$(( $(stat -c %s "$z") / 3 ))" "$z" > "$z.kurz" && mv "$z.kurz" "$z"
archiv --nur-pruefen --auftrag "$AUFTRAG_DATEI" > "$DATEN/archiv3.txt" 2>&1
rc=$?
pruefe "Prüflauf: Rückgabewert 1" gleich "$rc" 1
pruefe "Prüflauf meldet die abgeschnittene Fassung" gleich "$(ergebnis_von "$CSV" "$AUF/$K/GROSS_ENDUNG.MP4")" Fehler
pruefe "Prüflauf löscht nichts" datei_da "$z"
pruefe "Prüflauf: intakte Fassung vorhanden_ok" gleich "$(ergebnis_von "$CSV" "$AUF/$K/normal.mp4")" vorhanden_ok

echo "== 4. Zwei Aufträge gleichzeitig"
lang="$AUF/2026-01-05_Lang/lang.mp4"
mkdir -p "$(dirname "$lang")"
docker run --rm -v "$AUF:$AUF" "$IMAGE" -nostdin -hide_banner -loglevel error \
    -f lavfi -i testsrc2=size=1920x1080:rate=25:duration=1200 -c:v libx264 -preset ultrafast "$lang" < /dev/null
sleep 3
echo "$lang" > "$DATEN/A0002.txt"
setsid bash -c "ARCHIV_KONF='$KONF' '$BASH' '$SKRIPT' --auftrag '$DATEN/A0002.txt' > '$DATEN/archiv4a.txt' 2>&1" &
sleep 4
archiv --auftrag "$AUFTRAG_DATEI" > "$DATEN/archiv4b.txt" 2>&1
rc=$?
pruefe "zweiter Auftrag endet mit 2" gleich "$rc" 2

echo "== 5. Abbruch (wie systemctl stop: TERM an alle Prozesse)"
pgid="$(ps -o pgid= -p "$(pgrep -f "A0002.txt" | head -1)" | tr -d ' ')"
kill -TERM -- "-$pgid"
sleep 8
pruefe "keine Teildatei übrig" keine_teildateien
pruefe "keine Archiv-Fassung unter endgültigem Namen" datei_fehlt "$ZW/2026-01-05_Lang/lang.mp4.mov"
pruefe "kein Container läuft weiter" test -z "$(docker ps -q --filter name=archiv_)"
pruefe "Protokoll vermerkt den Abbruch" grep -q "abgebrochen" "$PROT/A0002.csv"
rm -rf "$AUF/2026-01-05_Lang"

echo "== 6. Bisheriger Aufruf: find | xargs -P 3"
rm -f "$ZW/2026-01-02_Telefon/"*.mov
find "$AUF/2026-01-02_Telefon/" -type f ! -name ".*" \( -iname "*.mp4" -o -iname "*.mov" \) -print0 |
    ARCHIV_KONF="$KONF" xargs -0 -n 1 -P 3 "$BASH" "$SKRIPT" > "$DATEN/archiv6.txt" 2>&1
rc=$?
pruefe "Rückgabewert 0" gleich "$rc" 0
pruefe "beide Telefonvideos umgerechnet" test "$(find "$ZW/2026-01-02_Telefon" -name '*.mov' | wc -l)" -eq 2
pruefe "Einzelprotokoll geschrieben" test -n "$(ls "$PROT"/einzel_*.csv 2>/dev/null)"

echo "== 6b. Aufruf mit --ordner"
rm -f "$ZW/2026-01-02_Telefon/"*.mov
archiv --ordner "$AUF/2026-01-02_Telefon" > "$DATEN/archiv6b.txt" 2>&1
rc=$?
pruefe "Rückgabewert 0" gleich "$rc" 0
pruefe "beide Telefonvideos umgerechnet" test "$(find "$ZW/2026-01-02_Telefon" -name '*.mov' | wc -l)" -eq 2
pruefe "Zusammenfassung ausgegeben" grep -q "Zusammenfassung" "$DATEN/archiv6b.txt"
pruefe ".mkv nicht angefasst" datei_fehlt "$ZW/2026-01-02_Telefon/keine_videoendung.mkv.mov"

echo "== 6c. Syncthing-Ordner"
st="$AUF/2026-01-06_Syncthing_Ingest"
mkdir -p "$st/.stfolder" "$st/Kamera"
cp "$AUF/$K/normal.mp4" "$st/Kamera/clip.mp4"
archiv "$st/Kamera/clip.mp4" > "$DATEN/archiv6c.txt" 2>&1
pruefe "Datei im Syncthing-Ordner: uebersprungen" grep -q "uebersprungen: .*Syncthing-Ordner" "$DATEN/archiv6c.txt"
pruefe "keine Archiv-Fassung" datei_fehlt "$ZW/2026-01-06_Syncthing_Ingest"
rm -rf "$st"

echo "== 7. Archiv-Fassung: volle Auflösung, 10 Bit"
info="$(docker run --rm -v "$AUF:$AUF:ro" --entrypoint ffprobe "$IMAGE" -v error -select_streams v:0 \
    -show_entries stream=width,height,pix_fmt,profile -of csv=p=0 "$ZW/$K/normal.mp4.mov" < /dev/null)"
pruefe "640x360, yuv420p10le, High 10 ($info)" gleich "$info" "High 10,640,360,yuv420p10le"

echo "== 8. ffmpeg-Aufruf anzeigen"
archiv --befehl "$AUF/$K/normal.mp4" > "$DATEN/archiv8.txt" 2>&1
pruefe "Parameter wie das alte Archivskript" grep -q -- '-c:v libx264 -c:a aac -preset veryfast -tune fastdecode -crf 18 -threads 4 -x264opts keyint=75 -f mov' "$DATEN/archiv8.txt"
pruefe "Quelle nur lesend, Ziel schreibbar eingebunden" grep -q -- "h264_archiv:.*h264_archiv " "$DATEN/archiv8.txt"

echo
echo "Bestanden: $bestanden, durchgefallen: $durchgefallen"
[ "$durchgefallen" -eq 0 ]
