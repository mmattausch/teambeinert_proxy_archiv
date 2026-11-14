# shellcheck shell=bash
# Profil „Archiv“: ffmpeg-Argumente des bestehenden archiv_h264.sh (Ist-Stand vom
# 09.01.2026, im Wissens-Repo unter docs/referenz/archiv_h264.IST-STAND.sh.txt).
#
# Grundsatz (Änderungsliste, Abschnitt 1): Die Funktion bleibt gleich. Parameter,
# Zielnamen und Ordnerstruktur wie bisher; Timecode und Ton-Zuordnung aus
# lib/v4_gemeinsam.sh (identisch mit dem alten Archivskript).
#
# Erlaubte Abweichungen (Änderungsliste M11): -nostdin, -f mov, Ausgabe .teil,
# --user, --name, kein -i bei docker run, gezielte Einbindungen statt -v /mnt:/mnt;
# dazu -hide_banner -loglevel error (nur kürzere Ausgabe).

PROFIL_KENNUNG="archiv_h264_crf18_v1"

# Platzbedarf vor dem Umrechnen (M14): Größe der Quelle plus Reserve. Eine Archiv-Fassung
# kann größer werden als das Original (z. B. HEVC vom Telefon).
profil_platzbedarf() {
    local g
    g="$(groesse "$QUELLE")"
    ist_zahl "${g:-x}" || g=0
    printf '%s\n' "$((g + RESERVE_BYTE))"
}

# ffmpeg-Argumente (alles nach dem Image bzw. nach "ffmpeg") in PROFIL_ARGS.
# $1 = Eingabe, $2 = Timecode, $3 = Ausgabedatei (Teildatei)
profil_ffmpeg_argumente() {
    local eingabe="$1" time_code="$2" ausgabe="$3"
    PROFIL_ARGS=(-nostdin -i "$eingabe" -pix_fmt yuv420p10le -timecode "$time_code")
    PROFIL_ARGS+=("${PROFIL_FILTER[@]}" "${PROFIL_VIDEO_MAP[@]}" "${PROFIL_AUDIO_MAP[@]}")
    PROFIL_ARGS+=(-c:v libx264 -c:a aac -preset veryfast -tune fastdecode -crf 18 -threads 4
        -x264opts keyint=75 -f mov "$ausgabe")
}

# Prüfung nach Änderungsliste M3 (angepasst 12.11.2026: nur die erste Videospur).
# Erwartet q_* (Original) und z_* (Archiv-Fassung) aus medien_eigenschaften.
profil_pruefen() {
    local toleranz="$1" groesse_ziel="$2"
    if [ "${z_ok:-0}" != "1" ]; then
        echo "Archiv-Fassung nicht lesbar"; return 1
    fi
    if ! ist_zahl "${groesse_ziel:-x}" || [ "$groesse_ziel" -le 0 ]; then
        echo "Archiv-Fassung ist leer"; return 1
    fi
    if ! laufzeit_passt "$q_laufzeit" "$z_laufzeit" "$toleranz"; then
        echo "Laufzeit weicht $(laufzeit_abweichung "$q_laufzeit" "$z_laufzeit") s ab (Original ${q_laufzeit:-?} s, Archiv-Fassung ${z_laufzeit:-?} s)"
        return 1
    fi
    if [ "${z_videospuren:-0}" -lt 1 ]; then
        echo "Archiv-Fassung hat keine Videospur"; return 1
    fi
    if [ "${z_breite:-}x${z_hoehe:-}" != "${q_breite:-}x${q_hoehe:-}" ]; then
        echo "Auflösung ${z_breite:-?}x${z_hoehe:-?} statt ${q_breite:-?}x${q_hoehe:-?} wie im Original"; return 1
    fi
    if [ "${z_tonkanaele:-0}" != "${q_tonkanaele:-0}" ]; then
        echo "Tonkanäle: Original ${q_tonkanaele:-0}, Archiv-Fassung ${z_tonkanaele:-0}"; return 1
    fi
    return 0
}
