#!/usr/bin/env bash
# Vergleicht die ffmpeg-Argumente von v4 und v5 Datei für Datei (Änderungsliste M11).
#
# v4 läuft unverändert bis auf die zwei Pfadvariablen (searchpath, basedir), mit einer
# Attrappe für "docker": ffprobe und der Timecode-Aufruf laufen wirklich (mit
# eingebundenem Testordner statt /mnt), der eigentliche ffmpeg-Aufruf wird nur
# mitgeschrieben. Danach dasselbe für v5 mit --befehl.
#
# Erlaubte Abweichungen (werden vor dem Vergleich entfernt):
#   -nostdin, -hide_banner, -loglevel error, -f mov vor der Ausgabe, Endung .teil.
# Alles andere muss gleich sein.
#
# Aufruf (Linux mit Docker, z. B. Colima-VM):
#   tests/v4_vergleich.sh [<Ordner mit Videodateien>]
# Standard: die Testdateien unter tests/daten (vorher tests/lauf_tests.sh oder
# tests/erzeuge_testdateien.sh tests/daten).

set -u
set -o pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DATEN="$REPO/tests/daten"
AUF="$DATEN/Aufnahmen"
ZEN="$DATEN/Proxy_Output/mnt/Aufnahmen"
V4_QUELLE="$REPO/../teambeinert_IT_wissen/docs/referenz/proxy_conv_docker_v4.IST-STAND.sh.txt"
ORDNER="${1:-$AUF/2026-01-01_Testprojekt/Kamera}"

[ -f "$V4_QUELLE" ] || { echo "v4 nicht gefunden: $V4_QUELLE" >&2; exit 2; }
[ -f "$DATEN/test.konf" ] || { echo "tests/daten/test.konf fehlt (erst tests/lauf_tests.sh laufen lassen)" >&2; exit 2; }

arbeit="$(mktemp -d)"
trap 'rm -rf "$arbeit"' EXIT

# v4 mit Testpfaden
sed -e "s#^searchpath=.*#searchpath=\"$AUF/\"#" \
    -e "s#^basedir=.*#basedir='$ZEN/'#" "$V4_QUELLE" > "$arbeit/v4.sh"
chmod +x "$arbeit/v4.sh"
if [ "$(diff "$V4_QUELLE" "$arbeit/v4.sh" | grep -c '^[<>]')" -ne 4 ]; then
    echo "Unerwartete Abweichung beim Anpassen von v4:" >&2
    diff "$V4_QUELLE" "$arbeit/v4.sh" >&2
    exit 2
fi

# Attrappe für docker
echte_docker="$(command -v docker)"
mkdir -p "$arbeit/bin"
cat > "$arbeit/bin/docker" <<EOF
#!/usr/bin/env bash
args=()
for a in "\$@"; do
    if [ "\$a" = "/mnt:/mnt" ]; then a="$AUF:$AUF"; fi
    args+=("\$a")
done
for a in "\$@"; do
    if [ "\$a" = "-c:v" ]; then
        printf '%s\0' "\$@" > "\$V4_ARGLOG"
        exit 0
    fi
done
exec "$echte_docker" "\${args[@]}"
EOF
chmod +x "$arbeit/bin/docker"

# Nur die Argumente nach dem Image, ohne erlaubte Abweichungen
nach_image() {
    local -a a=()
    local x hinter_image=0 vorher=""
    while IFS= read -r -d '' x; do
        if [ "$hinter_image" = 0 ]; then
            case "$x" in linuxserver/ffmpeg*) hinter_image=1 ;; esac
            continue
        fi
        case "$x" in
            -nostdin | -hide_banner) continue ;;
        esac
        if [ "$vorher" = "-loglevel" ] && [ "$x" = "error" ]; then vorher=""; unset 'a[-1]'; continue; fi
        if [ "$vorher" = "-f" ] && [ "$x" = "mov" ]; then vorher=""; unset 'a[-1]'; continue; fi
        x="${x%.teil}"
        a+=("$x")
        vorher="$x"
    done
    printf '%s\n' "${a[@]}"
}

gleich=0
ungleich=0
erwartet=0
while IFS= read -r -d '' datei; do
    rm -f "$arbeit/v4_args"
    # Damit v4 umrechnen will, dürfen keine Proxys da sein: Ziele in leere Ordner lenken
    rel="${datei#"$AUF"/}"
    name="$(basename -- "$datei")"
    lokal="$(dirname -- "$datei")/Proxies/${name%.*}.mov"
    zentral="$ZEN/$rel.mov"
    for f in "$lokal" "$zentral"; do
        [ -e "$f" ] && mv -- "$f" "$f.vergleich_weg"
    done
    PATH="$arbeit/bin:$PATH" V4_ARGLOG="$arbeit/v4_args" "$arbeit/v4.sh" "$datei" < /dev/null > /dev/null 2>&1
    BEFEHL_ZEILENWEISE=1 PROXY_V5_KONF="$DATEN/test.konf" "$BASH" "$REPO/proxy_v5.sh" --befehl "$datei" < /dev/null > "$arbeit/v5_args" 2>/dev/null
    for f in "$lokal" "$zentral"; do
        [ -e "$f.vergleich_weg" ] && mv -- "$f.vergleich_weg" "$f"
    done
    if [ ! -s "$arbeit/v4_args" ]; then
        printf 'v4 ohne ffmpeg  %s\n' "$rel"
        continue
    fi
    # Bekannte Fehler von v4, bei denen v5 bewusst anders ist
    v4_eingabe="$(nach_image < "$arbeit/v4_args" | sed -n '2p')"
    if [ ! -s "$arbeit/v5_args" ]; then
        printf 'erwartet        %s (v5 rechnet nicht: Quelle für ffprobe nicht lesbar; v4 versucht es)\n' "$rel"
        erwartet=$((erwartet + 1))
        continue
    fi
    if [ "$v4_eingabe" != "$datei" ]; then
        printf 'erwartet        %s (v4 zerlegt den Dateinamen mit eval: %s)\n' "$rel" "$(basename -- "$v4_eingabe")"
        erwartet=$((erwartet + 1))
        continue
    fi
    if tr '\0' '\n' < "$arbeit/v4_args" | grep -qx '0:a-map'; then
        printf 'erwartet        %s (v4: fehlendes Leerzeichen in der Ton-Zuordnung, ffmpeg scheitert in beiden)\n' "$rel"
        erwartet=$((erwartet + 1))
        continue
    fi
    if diff <(nach_image < "$arbeit/v4_args") <(nach_image < "$arbeit/v5_args") > "$arbeit/diff"; then
        printf 'gleich          %s\n' "$rel"
        gleich=$((gleich + 1))
    else
        printf 'UNGLEICH        %s\n' "$rel"
        sed 's/^/                    /' "$arbeit/diff"
        ungleich=$((ungleich + 1))
    fi
done < <(find "$ORDNER" -maxdepth 1 -type f ! -name '.*' \
    \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) -print0 | sort -z)

echo
echo "Gleich: $gleich, erwartete Unterschiede (Fehler von v4): $erwartet, ungleich: $ungleich"
[ "$ungleich" -eq 0 ]
