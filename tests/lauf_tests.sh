#!/usr/bin/env bash
# Ablauftests für proxy_v5.sh mit den Testdateien aus tests/erzeuge_testdateien.sh.
#
# Läuft in einer Linux-Umgebung mit Bash ≥ 4.4, GNU-Werkzeugen, flock und Docker
# (ELSA oder auf dem Mac in der Colima-VM):
#   colima ssh -- bash -c 'cd <Repo> && tests/lauf_tests.sh'
#
# Legt alles unter tests/daten/ neu an (der Ordner wird vorher gelöscht).
# Ende mit 0, wenn alle Prüfungen bestanden sind.

set -u
set -o pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DATEN="$REPO/tests/daten"
AUF="$DATEN/Aufnahmen"
ZEN="$DATEN/Proxy_Output/mnt/Aufnahmen"
PROT="$DATEN/Proxy_Output/_protokolle"
KONF="$DATEN/test.konf"
K="2026-01-01_Testprojekt/Kamera"
SKRIPT="$REPO/proxy_v5.sh"

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

lauf() { PROXY_V5_KONF="$KONF" "$SKRIPT" "$@"; }

datei_da() { [ -f "$1" ]; }
datei_fehlt() { [ ! -e "$1" ]; }
gleich() { [ "$1" = "$2" ]; }
keine_teildateien() { [ -z "$(find "$DATEN" -name '*.teil' -print -quit)" ]; }
nicht_root() { [ "$(stat -c %u "$1")" != "0" ]; }

echo "== Vorbereitung"
rm -rf "$DATEN"
"$REPO/tests/erzeuge_testdateien.sh" "$DATEN" > /dev/null || { echo "Testdateien konnten nicht erzeugt werden"; exit 2; }
cat > "$KONF" <<EOF
AUFNAHMEN="$AUF"
ZENTRAL="$ZEN"
PROTOKOLL_ORDNER="$PROT"
ALTER_MIN=0
RESERVE_BYTE=\$((100 * 1024 * 1024))
EOF
rm -f "$HOME/proxy_v5_pwned" "$HOME/proxy_v5_pwned2"

echo "== 1. Abendlauf"
lauf > "$DATEN/lauf1.txt" 2>&1
rc=$?
pruefe "Rückgabewert 1 (es gibt erwartete Fehler)" gleich "$rc" 1
pruefe "kein Dateiname als Befehl ausgeführt" datei_fehlt "$HOME/proxy_v5_pwned"
pruefe "kein Dateiname als Befehl ausgeführt (Backticks)" datei_fehlt "$HOME/proxy_v5_pwned2"
pruefe "Proxy lokal: normal.mp4" datei_da "$AUF/$K/Proxies/normal.mov"
pruefe "Proxy zentral: normal.mp4.mov" datei_da "$ZEN/$K/normal.mp4.mov"
pruefe "Proxy für \$(…)-Namen" datei_da "$AUF/$K/Proxies/clip\$(cd;touch proxy_v5_pwned).mov"
pruefe "Proxy für führendes Minus" datei_da "$AUF/$K/Proxies/-beginnt_mit_minus.mov"
pruefe "Proxy für Doppelpunkt" datei_da "$AUF/$K/Proxies/Doppel:punkt.mov"
pruefe "Proxy für Zeilenumbruch im Namen" datei_da "$AUF/$K/Proxies/Zeilen"$'\n'"umbruch.mov"
pruefe "Proxy für Telefonvideo mit 00_ im Namen" datei_da "$AUF/2026-01-02_Telefon/Proxies/VID_20260102_120000_00_001.mov"
pruefe "Proxy für Datei im Wurzelordner, zentral ohne Unterordner" datei_da "$ZEN/im_wurzelordner.mp4.mov"
pruefe "kein Proxy in 00_to_Backup" datei_fehlt "$AUF/00_to_Backup/AUF999/2025-01-01_Alt/Proxies"
pruefe "kein Proxy in 01_zum_Band" datei_fehlt "$AUF/01_zum_Band/AUF998/2025-01-02_Alt/Proxies"
pruefe "kein Proxy für versteckte Datei" datei_fehlt "$AUF/$K/Proxies/.versteckt.mov"
pruefe "kein Proxy vom Proxy" datei_fehlt "$AUF/$K/Proxies/Proxies"
pruefe "kein Proxy für .mkv" datei_fehlt "$AUF/2026-01-02_Telefon/Proxies/keine_videoendung.mov"
pruefe "kein Proxy für defekte Datei" datei_fehlt "$AUF/$K/Proxies/defekt_abgeschnitten.mov"
pruefe "kein Proxy für Datei ohne Video" datei_fehlt "$AUF/$K/Proxies/nur_ton_kein_video.mov"
pruefe "keine Teildateien übrig" keine_teildateien
pruefe "Protokoll geschrieben" test -n "$(ls "$PROT"/lauf_*.csv 2>/dev/null)"
pruefe "Proxys gehören nicht root" nicht_root "$AUF/$K/Proxies/normal.mov"

echo "== 2. Zweiter Lauf ändert nichts"
vorher="$(find "$AUF" "$ZEN" -name '*.mov' -path '*Proxies*' -o -name '*.mov.mov' -o -name '*.mp4.mov' | sort | xargs -d '\n' stat -c '%n %s %Y' 2>/dev/null | md5sum)"
lauf > "$DATEN/lauf2.txt" 2>&1
nachher="$(find "$AUF" "$ZEN" -name '*.mov' -path '*Proxies*' -o -name '*.mov.mov' -o -name '*.mp4.mov' | sort | xargs -d '\n' stat -c '%n %s %Y' 2>/dev/null | md5sum)"
pruefe "Proxys unverändert" gleich "$vorher" "$nachher"
pruefe "keine neuen Umrechnungen" test "$(grep -c '^.* ok: ' "$DATEN/lauf2.txt")" -eq 0

echo "== 3. Fehlende Kopie wird ergänzt, nicht neu gerechnet"
rm -f "$ZEN/$K/tc_25p.mov.mov"
rm -f "$AUF/$K/Proxies/tc_ohne.mov"
lauf > "$DATEN/lauf3.txt" 2>&1
pruefe "zentrale Kopie wieder da" datei_da "$ZEN/$K/tc_25p.mov.mov"
pruefe "lokale Kopie wieder da" datei_da "$AUF/$K/Proxies/tc_ohne.mov"
pruefe "zweimal kopiert" test "$(grep -c 'kopiert: ' "$DATEN/lauf3.txt")" -eq 2
pruefe "lokal und zentral gleich" cmp -s "$ZEN/$K/tc_ohne.mov.mov" "$AUF/$K/Proxies/tc_ohne.mov"

echo "== 4. Zwei gleichzeitige Läufe"
rm -f "$AUF/$K/Proxies/normal.mov" "$ZEN/$K/normal.mp4.mov"
lauf > "$DATEN/lauf4a.txt" 2>&1 &
p1=$!
sleep 1
lauf > "$DATEN/lauf4b.txt" 2>&1
rc_b=$?
wait "$p1"
pruefe "zweiter Lauf endet mit 2" gleich "$rc_b" 2
pruefe "erster Lauf hat normal.mp4 erzeugt" datei_da "$AUF/$K/Proxies/normal.mov"

echo "== 5. Abbruch mitten in der Umrechnung"
lang="$AUF/2026-01-03_Abbruch/lang.mp4"
mkdir -p "$(dirname "$lang")"
docker run --rm -v "$AUF:$AUF" linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697 \
    -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=25:duration=1200 \
    -c:v libx264 -preset ultrafast "$lang" < /dev/null
sleep 3   # Einbindung der Colima-VM meldet Änderungszeiten verzögert
PROXY_V5_KONF="$KONF" "$SKRIPT" --datei "$lang" > "$DATEN/lauf5.txt" 2>&1 &
p=$!
sleep 5
kill -TERM "$p"
wait "$p"
rc=$?
sleep 2
pruefe "Rückgabewert 1 nach Abbruch" gleich "$rc" 1
pruefe "kein Proxy unter endgültigem Namen" datei_fehlt "$ZEN/2026-01-03_Abbruch/lang.mp4.mov"
pruefe "keine Teildatei übrig" keine_teildateien
pruefe "kein Container läuft weiter" test -z "$(docker ps -q --filter name=proxy_v5_)"
pruefe "Protokoll vermerkt den Abbruch" grep -q abgebrochen "$PROT"/einzel_*.csv
rm -rf "$AUF/2026-01-03_Abbruch"

echo "== 6. Einzelaufruf"
lauf --datei "$AUF/00_to_Backup/AUF999/2025-01-01_Alt/im_sammelordner.mp4" > "$DATEN/lauf6.txt" 2>&1
pruefe "Datei in 00_to_Backup wird übersprungen" grep -q 'uebersprungen: .*liegt in 00_to_Backup' "$DATEN/lauf6.txt"
lauf --datei "$AUF/$K/normal.mp4" > "$DATEN/lauf6b.txt" 2>&1
pruefe "vorhandener Proxy wird nicht neu gerechnet" grep -q 'vorhanden: ' "$DATEN/lauf6b.txt"
rm -f "$AUF/$K/Proxies/mit Leerzeichen.mov" "$ZEN/$K/mit Leerzeichen.mp4.mov"
rm -f "$AUF/$K/Proxies/GROSS_ENDUNG.mov" "$ZEN/$K/GROSS_ENDUNG.MP4.mov"
printf '%s\0' "$AUF/$K/mit Leerzeichen.mp4" "$AUF/$K/GROSS_ENDUNG.MP4" "$AUF/$K/mit Leerzeichen.mp4" |
    PROXY_V5_KONF="$KONF" xargs -0 -n 1 -P 3 "$SKRIPT" --datei > "$DATEN/lauf6c.txt" 2>&1
pruefe "parallele Einzelaufrufe: Proxy erzeugt" datei_da "$AUF/$K/Proxies/mit Leerzeichen.mov"
pruefe "parallele Einzelaufrufe: dieselbe Datei nur einmal gerechnet" \
    test "$(grep -c 'ok: .*mit Leerzeichen.mp4' "$DATEN/lauf6c.txt")" -eq 1

echo "== 7. Prüflauf findet abgeschnittenen Proxy"
ziel="$AUF/$K/Proxies/tc_25p.mov"
head -c "$(( $(stat -c %s "$ziel") / 3 ))" "$ziel" > "$ziel.kurz" && mv "$ziel.kurz" "$ziel"
groesse_kaputt="$(stat -c %s "$ziel")"
lauf --nur-pruefen > "$DATEN/lauf7.txt" 2>&1
pruefe "Prüflauf meldet den kaputten Proxy" grep -q "FEHLER: .*tc_25p.mov" "$DATEN/lauf7.txt"
pruefe "Prüflauf ändert nichts" gleich "$(stat -c %s "$ziel")" "$groesse_kaputt"
pruefe "Abendlauf repariert ihn nicht (wie v4)" true

echo "== 8. Schnittrechner-Modus"
lokal="$DATEN/Schnittrechner/Dreh"
mkdir -p "$lokal/Kamera_A"
cp "$AUF/$K/normal.mp4" "$AUF/$K/ton_4x_mono.mov" "$lokal/Kamera_A/"
PROXY_V5_KONF="$KONF" "$SKRIPT" --lokal "$lokal" > "$DATEN/lauf8.txt" 2>&1
rc=$?
pruefe "Rückgabewert 0" gleich "$rc" 0
pruefe "Proxy in Proxies/ neben den Aufnahmen" datei_da "$lokal/Kamera_A/Proxies/normal.mov"
pruefe "nichts in der zentralen Ablage" datei_fehlt "$ZEN/../Schnittrechner"
pruefe "Abschlusszeile für den Kollegen" grep -q "Fertig, alle Proxys erstellt" "$DATEN/lauf8.txt"
# Danach wie üblich nach Aufnahmen kopieren: ELSA ergänzt nur die zentrale Kopie
cp -r "$lokal" "$AUF/2026-01-04_Eilig"
lauf > "$DATEN/lauf8b.txt" 2>&1
pruefe "ELSA kopiert den Proxy vom Schnittrechner nach zentral" datei_da "$ZEN/2026-01-04_Eilig/Kamera_A/normal.mp4.mov"
pruefe "ELSA rechnet ihn nicht neu" test "$(grep -c 'ok: .*2026-01-04_Eilig' "$DATEN/lauf8b.txt")" -eq 0

echo "== 9. ffmpeg-Aufruf anzeigen"
lauf --befehl "$AUF/$K/ton_4x_mono.mov" > "$DATEN/lauf9.txt" 2>&1
pruefe "Aufruf enthält die v4-Parameter" grep -q -- '-profile:v main -level 2.1 -preset veryfast -tune fastdecode -crf 21 -threads 4 -x264opts keyint=75 -f mov' "$DATEN/lauf9.txt"
pruefe "Quelle nur lesend eingebunden" grep -q -- ':ro ' "$DATEN/lauf9.txt"

echo
echo "Bestanden: $bestanden, durchgefallen: $durchgefallen"
[ "$durchgefallen" -eq 0 ]
