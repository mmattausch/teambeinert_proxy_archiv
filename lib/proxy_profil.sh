# shellcheck shell=bash
# Profil „Proxy“: ffmpeg-Argumente, Timecode und Ton-Zuordnung, Zeile für Zeile aus
# proxy_conv_docker_v4.sh übertragen (Ist-Stand 09.01.2026, sha256 36e29763…).
#
# Grundsatz: Die Funktion bleibt gleich. Auch Eigenheiten von v4 bleiben erhalten
# (Befunde 1–8 im Plan), z. B. -level 2.1, scale=-1:540, die Ton-Zuordnung mit
# -map 0:0 -map 0:1 bei mehr als 8 Kanälen. Eine Änderung wäre ein neues Profil.
#
# Erlaubte Abweichungen vom v4-Aufruf (Änderungsliste M11):
#   -nostdin, -f mov, Ausgabe .teil, --user, --name, kein -i bei docker run,
#   gezielte Einbindungen statt -v /mnt:/mnt.

PROFIL_KENNUNG="proxy_h264_540_v1"
PROFIL_HOEHE=540

# Platzbedarf vor dem Umrechnen (M14): feste Reserve, Proxys sind klein
profil_platzbedarf() { printf '%s\n' "$RESERVE_BYTE"; }

# ffmpeg-Argumente (alles nach dem Image bzw. nach "ffmpeg") in PROFIL_ARGS.
# $1 = Eingabe, $2 = Timecode, $3 = Ausgabedatei (Teildatei)
profil_ffmpeg_argumente() {
    local eingabe="$1" time_code="$2" ausgabe="$3"
    PROFIL_ARGS=(-nostdin -i "$eingabe" -vf scale=-1:540 -pix_fmt yuv420p -timecode "$time_code")
    PROFIL_ARGS+=("${PROFIL_FILTER[@]}" "${PROFIL_VIDEO_MAP[@]}" "${PROFIL_AUDIO_MAP[@]}")
    PROFIL_ARGS+=(-c:v libx264 -c:a aac -profile:v main -level 2.1 -preset veryfast -tune fastdecode
        -crf 21 -threads 4 -x264opts keyint=75 -f mov "$ausgabe")
}

# Prüfung nach dem Umrechnen (Änderungsliste M3, angepasst 12.11.2026).
# Erwartet q_* (Original) und z_* (Proxy) aus medien_eigenschaften.
# Gibt bei Fehler den Grund auf stdout aus und endet mit 1.
profil_pruefen() {
    local toleranz="$1" groesse_ziel="$2"
    if [ "${z_ok:-0}" != "1" ]; then
        echo "Proxy nicht lesbar"; return 1
    fi
    if ! ist_zahl "${groesse_ziel:-x}" || [ "$groesse_ziel" -le 0 ]; then
        echo "Proxy ist leer"; return 1
    fi
    if ! laufzeit_passt "$q_laufzeit" "$z_laufzeit" "$toleranz"; then
        echo "Laufzeit weicht $(laufzeit_abweichung "$q_laufzeit" "$z_laufzeit") s ab (Original ${q_laufzeit:-?} s, Proxy ${z_laufzeit:-?} s)"
        return 1
    fi
    if [ "${z_videospuren:-0}" -lt 1 ]; then
        echo "Proxy hat keine Videospur"; return 1
    fi
    if [ "${z_hoehe:-}" != "$PROFIL_HOEHE" ]; then
        echo "erste Videospur ist ${z_hoehe:-?} Pixel hoch statt $PROFIL_HOEHE"; return 1
    fi
    # Ton: Der Proxy hat Ton genau dann, wenn das Original Ton hat. Die Kanalzahl wird
    # beim Proxy bewusst nicht verglichen: v4 erzeugt bei 3/5/7 Kanälen und gemischten
    # Spuren mehr Spuren als das Original (Befunde 1 und 2). Solche Proxys sind im Schnitt
    # brauchbar; eine strengere Prüfung würde dort gar keinen Proxy mehr liefern.
    # (Abweichung von Änderungsliste M3, von Michl bestätigt am 13.11.2026; beim Archiv bleibt
    # der Vergleich der Kanalsumme.)
    if [ "${q_tonkanaele:-0}" -gt 0 ] && [ "${z_tonkanaele:-0}" -eq 0 ]; then
        echo "Proxy hat keinen Ton, das Original schon"; return 1
    fi
    if [ "${q_tonkanaele:-0}" -eq 0 ] && [ "${z_tonkanaele:-0}" -gt 0 ]; then
        echo "Proxy hat Ton, das Original nicht"; return 1
    fi
    return 0
}
