#!/usr/bin/env bash
# Gleichheitstest v4 gegen v5 am Testkorpus (Plan, Abschnitte 6 und 10).
#
# Liest den Testordner nur. Schreibt ausschließlich ins Testverzeichnis.
#
# Ablauf je Originaldatei:
#   1. v4 rechnet: das echte proxy_conv_docker_v4.sh, nur die Pfadvariablen
#      basedir, proxydest und proxydestfile zeigen ins Testverzeichnis.
#   2. v5 rechnet: der Aufruf aus "proxy_v5.sh --befehl", Ziel im Testverzeichnis.
#   3. Vergleich: Bild und Ton per framemd5, Spuren per ffprobe, dazu die Prüfung
#      nach M3 aus lib/proxy_profil.sh für den v5-Proxy.
#
# Aufruf (auf ELSA als root, per systemd-run):
#   tests/korpus_vergleich.sh [<Testordner>] [<Testverzeichnis>] [<v4-Skript>]
# Standard:
#   Testordner      /mnt/Aufnahme_mirror/Aufnahmen/2025-03-04_PROXY
#   Testverzeichnis /mnt/Mirror_2x8TB/Proxy_Output/_test
#   v4-Skript       /mnt/Mirror_2x8TB/Proxy_Output/proxy_conv_docker_v4.sh
#
# Ergebnis: <Testverzeichnis>/vergleich_<Zeit>.csv und Zusammenfassung auf der Ausgabe.
# Rückgabewert 0, wenn alle Dateien gleich sind oder der Unterschied erklärt ist.

set -u
set -o pipefail
umask 0002

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KORPUS="${1:-/mnt/Aufnahme_mirror/Aufnahmen/2025-03-04_PROXY}"
TEST="${2:-/mnt/Mirror_2x8TB/Proxy_Output/_test}"
V4="${3:-/mnt/Mirror_2x8TB/Proxy_Output/proxy_conv_docker_v4.sh}"
V4_SHA256="36e297631dfbf5bf10a75186c2c04cf947929598767bd6e965385d5fd7ad4132"
AUFNAHMEN="${AUFNAHMEN:-/mnt/Aufnahme_mirror/Aufnahmen}"

zeit() { date '+%Y-%m-%d %H:%M:%S'; }
meldung() { printf '%s %s\n' "$(zeit)" "$*"; }

# --- Vorprüfungen -----------------------------------------------------------

[ -d "$KORPUS" ] || { echo "Testordner nicht gefunden: $KORPUS" >&2; exit 2; }
case "$KORPUS" in
    "$AUFNAHMEN"/*) ;;
    *) echo "Testordner muss unter $AUFNAHMEN liegen (für v4 und v5 gleich): $KORPUS" >&2; exit 2 ;;
esac
[ -f "$V4" ] || { echo "v4 nicht gefunden: $V4" >&2; exit 2; }
if [ "${V4_PRUEFSUMME_IGNORIEREN:-0}" != "1" ] && [ "$(sha256sum "$V4" | cut -d' ' -f1)" != "$V4_SHA256" ]; then
    echo "v4 hat nicht die erwartete Prüfsumme ($V4_SHA256)." >&2
    exit 2
fi
mkdir -p "$TEST" || exit 2
stempel="$(date '+%Y-%m-%d_%H%M%S')"
ARBEIT="$TEST/lauf_$stempel"
mkdir -p "$ARBEIT/v4/zentral" "$ARBEIT/v4/lokal" "$ARBEIT/v5/zentral" "$ARBEIT/v5/protokolle" "$ARBEIT/md5" || exit 2

# v5-Einstellungen: Quelle wie auf ELSA, Ziel im Testverzeichnis
cat > "$ARBEIT/v5.konf" <<EOF
AUFNAHMEN="$AUFNAHMEN"
ZENTRAL="$ARBEIT/v5/zentral"
PROTOKOLL_ORDNER="$ARBEIT/v5/protokolle"
EOF

# v4-Testfassung: nur Pfadvariablen geändert
sed -e "s#^basedir=.*#basedir='$ARBEIT/v4/zentral/'#" \
    -e "s#^proxydest=\"\$dest/Proxies\"#proxydest=\"$ARBEIT/v4/lokal\$dest/Proxies\"#" \
    -e "s#^proxydestfile=\"\${dest}/Proxies/\${xpref}.mov\"#proxydestfile=\"$ARBEIT/v4/lokal\${dest}/Proxies/\${xpref}.mov\"#" \
    "$V4" > "$ARBEIT/v4_test.sh"
chmod +x "$ARBEIT/v4_test.sh"
geaendert="$(diff "$V4" "$ARBEIT/v4_test.sh" | grep -c '^>')"
if [ "$geaendert" -ne 3 ]; then
    echo "v4 ließ sich nicht wie erwartet anpassen (geänderte Zeilen: $geaendert):" >&2
    diff "$V4" "$ARBEIT/v4_test.sh" >&2
    exit 2
fi
diff "$V4" "$ARBEIT/v4_test.sh" > "$ARBEIT/v4_aenderungen.diff"

# Kern und Profil von v5 für Prüfung und ffprobe
# shellcheck source=../lib/kern.sh
source "$REPO/lib/kern.sh"
# shellcheck source=../lib/proxy_profil.sh
source "$REPO/lib/proxy_profil.sh"
FFMPEG_IMAGE="$(sed -n 's/^FFMPEG_IMAGE="\(.*\)"/\1/p' "$REPO/proxy_v5.sh")"
CONTAINER_USER=""
EINBINDUNGEN_LESEN=("$AUFNAHMEN" "$ARBEIT")
EINBINDUNGEN_SCHREIBEN=()

if ! docker image inspect "$FFMPEG_IMAGE" > /dev/null 2>&1; then
    echo "Image nicht vorhanden: $FFMPEG_IMAGE (es wird nichts geladen)" >&2
    exit 2
fi
v4_image="$(docker image inspect linuxserver/ffmpeg --format '{{index .RepoDigests 0}}' 2>/dev/null)"
if [ "${v4_image#*@}" != "${FFMPEG_IMAGE#*@}" ] && [ "${IMAGE_PRUEFUNG_IGNORIEREN:-0}" != "1" ]; then
    echo "v4 nutzt linuxserver/ffmpeg = $v4_image, v5 $FFMPEG_IMAGE: nicht dasselbe Image." >&2
    exit 2
fi

# framemd5 von Bild und Ton (ohne Datenspuren) in eine Datei
md5_bild_ton() {
    local datei="$1" ziel="$2"
    local -a cmd
    container_vorspann cmd ffmpeg ""
    "${cmd[@]}" -nostdin -hide_banner -loglevel error -i "$datei" -map 0:v -map '0:a?' -f framemd5 - \
        < /dev/null 2>/dev/null | grep -v '^#' > "$ziel"
}

spuren() {
    ffprobe_lauf -v error -show_entries stream=codec_type,codec_name,profile,level,width,height,pix_fmt,channels \
        -of compact=p=0:nk=1 "$1" 2>/dev/null | tr '\n' ' '
}

# --- Lauf -------------------------------------------------------------------

ERG="$TEST/vergleich_$stempel.csv"
csv_zeile datei ergebnis grund v4_rc v5_rc v4_sekunden v5_sekunden v4_groesse v5_groesse pruefung_v5 > "$ERG"

gleich=0; erklaert=0; ungleich=0; nr=0
anzahl="$(find "$KORPUS" -type f ! -name '.*' ! -path '*/Proxies/*' \
    \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) | wc -l)"
meldung "Korpus $KORPUS: $anzahl Dateien. Arbeitsordner $ARBEIT"

while IFS= read -r -d '' datei; do
    nr=$((nr + 1))
    rel="${datei#"$AUFNAHMEN"/}"
    meldung "[$nr/$anzahl] $rel"

    # v4
    t0=$(date +%s)
    "$ARBEIT/v4_test.sh" "$datei" < /dev/null > "$ARBEIT/v4_ausgabe_$nr.txt" 2>&1
    v4_rc=$?
    v4_sek=$(( $(date +%s) - t0 ))
    v4_datei="$ARBEIT/v4/zentral/$rel.mov"

    # v5
    QUELLE="$datei"
    v5_ziel="$ARBEIT/v5/zentral/$rel.mov"
    mkdir -p "$(dirname -- "$v5_ziel")"
    t0=$(date +%s)
    befehl=()
    while IFS= read -r -d '' x; do befehl+=("$x"); done < <(
        BEFEHL_ZEILENWEISE=1 PROXY_V5_KONF="$ARBEIT/v5.konf" "$REPO/proxy_v5.sh" --befehl "$datei" < /dev/null 2> "$ARBEIT/v5_befehl_$nr.txt")
    v5_rc=99
    if [ "${#befehl[@]}" -gt 0 ]; then
        "${befehl[@]}" < /dev/null > "$ARBEIT/v5_ausgabe_$nr.txt" 2>&1
        v5_rc=$?
        [ "$v5_rc" -eq 0 ] && mv -f -- "$v5_ziel.teil" "$v5_ziel"
        rm -f -- "$v5_ziel.teil"
    fi
    v5_sek=$(( $(date +%s) - t0 ))

    v4_g="$(groesse "$v4_datei")"
    v5_g="$(groesse "$v5_ziel")"

    # Prüfung nach M3 für den v5-Proxy
    pruefung=""
    if [ -f "$v5_ziel" ]; then
        medien_eigenschaften "$datei" q
        medien_eigenschaften "$v5_ziel" z
        if pruefung="$(profil_pruefen 1.0 "$v5_g")"; then pruefung="ok"; fi
    fi

    # Vergleich
    ergebnis=""; grund=""
    name="$(basename -- "$datei")"
    if [ -f "$v4_datei" ] && [ "${v4_g:-0}" = "0" ] && [ ! -f "$v5_ziel" ]; then
        ergebnis="erklaert"; grund="ffmpeg scheitert in beiden; v4 hinterlässt eine leere Datei (0 Byte), v5 meldet Fehler"
    elif [ ! -f "$v4_datei" ] && [ ! -f "$v5_ziel" ]; then
        ergebnis="erklaert"; grund="beide liefern keinen Proxy"
    elif [ ! -f "$v4_datei" ] && [[ "$name" == *[\"\'\$\`\\]* || "$name" == *$'\n'* ]]; then
        ergebnis="erklaert"; grund="v4 zerlegt den Dateinamen mit eval, v5 rechnet richtig"
    elif [ ! -f "$v4_datei" ]; then
        ergebnis="ungleich"; grund="nur v5 liefert einen Proxy"
    elif [ ! -f "$v5_ziel" ]; then
        ergebnis="ungleich"; grund="nur v4 liefert einen Proxy"
    else
        md5_bild_ton "$v4_datei" "$ARBEIT/md5/v4_$nr.txt"
        md5_bild_ton "$v5_ziel" "$ARBEIT/md5/v5_$nr.txt"
        if [ ! -s "$ARBEIT/md5/v4_$nr.txt" ]; then
            ergebnis="ungleich"; grund="v4-Proxy nicht dekodierbar"
        elif cmp -s "$ARBEIT/md5/v4_$nr.txt" "$ARBEIT/md5/v5_$nr.txt"; then
            ergebnis="gleich"; grund="Bild und Ton identisch"
        elif [ "$(spuren "$v4_datei")" = "$(spuren "$v5_ziel")" ]; then
            ergebnis="ungleich"; grund="Spuren gleich, Bild oder Ton verschieden"
        else
            ergebnis="ungleich"; grund="Spuren verschieden: v4 $(spuren "$v4_datei") / v5 $(spuren "$v5_ziel")"
        fi
    fi
    case "$ergebnis" in
        gleich) gleich=$((gleich + 1)) ;;
        erklaert) erklaert=$((erklaert + 1)) ;;
        *) ungleich=$((ungleich + 1)) ;;
    esac
    meldung "    $ergebnis: $grund (v4 ${v4_sek} s, v5 ${v5_sek} s; Prüfung v5: ${pruefung:-kein Proxy})"
    csv_zeile "$rel" "$ergebnis" "$grund" "$v4_rc" "$v5_rc" "$v4_sek" "$v5_sek" "$v4_g" "$v5_g" "$pruefung" >> "$ERG"
done < <(find "$KORPUS" -type f ! -name '.*' ! -path '*/Proxies/*' \
    \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) -print0 | sort -z)

echo
meldung "Fertig. Gleich: $gleich, erklärt: $erklaert, ungleich: $ungleich. Ergebnis: $ERG"
[ "$ungleich" -eq 0 ]
