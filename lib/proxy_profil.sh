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

# Timecode wie v4: erster Treffer in der Textausgabe von "ffmpeg -i", sonst 00:00:00:00.
# ([[:space:]] statt \s, gleiche Bedeutung, auch mit nicht-GNU-grep.)
profil_timecode() {
    local eingabe="$1" tc
    local -a cmd
    container_vorspann cmd ffmpeg ""
    tc="$("${cmd[@]}" -nostdin -i "$eingabe" < /dev/null 2>&1 \
        | grep -Eo 'timecode[[:space:]]*:[[:space:]]*[0-9]{2}:[0-9]{2}:[0-9]{2}[;:][0-9]{2}' \
        | awk '{print $NF}' | head -n 1)"
    if [ -z "$tc" ]; then
        tc="00:00:00:00"
    fi
    printf '%s\n' "$tc"
}

# Ton-Zuordnung wie v4. Setzt die Arrays PROFIL_FILTER, PROFIL_VIDEO_MAP, PROFIL_AUDIO_MAP.
#
# v4 überschreibt bei jeder Spur bis 8 Kanäle (bzw. 4/6/8) audio_map und video_map
# und hängt bei allen anderen Kanalzahlen Monospuren an. Das wird hier exakt
# nachgebildet, einschließlich der Fälle 3/5/7 Kanäle (else-Zweig) und gemischter Spuren.
profil_ton_zuordnung() {
    local eingabe="$1" ausgabe stream_index num_channels i audio_index=0 filter_complex=""
    PROFIL_FILTER=()
    PROFIL_VIDEO_MAP=()
    PROFIL_AUDIO_MAP=()

    ausgabe="$(ffprobe_lauf -v error -select_streams a \
        -show_entries stream=index,channels -of csv=p=0 "$eingabe")" || return 1

    if [ -z "$ausgabe" ]; then
        return 0
    fi

    while IFS=',' read -r stream_index num_channels; do
        if ist_zahl "${num_channels:-x}" && [ "$num_channels" -le 2 ]; then
            PROFIL_AUDIO_MAP=(-map 0:a)
            PROFIL_VIDEO_MAP=(-map 0:v)
        elif ist_zahl "${num_channels:-x}" && [ "$num_channels" -eq 4 ]; then
            PROFIL_AUDIO_MAP=(-map 0:a)
            PROFIL_VIDEO_MAP=(-map 0:v)
        elif ist_zahl "${num_channels:-x}" && [ "$num_channels" -eq 6 ]; then
            PROFIL_AUDIO_MAP=(-map 0:a)
            PROFIL_VIDEO_MAP=(-map 0:v)
        elif ist_zahl "${num_channels:-x}" && [ "$num_channels" -eq 8 ]; then
            PROFIL_AUDIO_MAP=(-map 0:a)
            PROFIL_VIDEO_MAP=(-map 0:v)
        else
            # Wie v4: auch 3/5/7 Kanäle landen hier. Eine nicht lesbare Kanalzahl
            # ergibt in v4 null Durchläufe; ebenso hier.
            ist_zahl "${num_channels:-x}" || num_channels=0
            for ((i = 0; i < num_channels; i++)); do
                filter_complex+="[0:a]pan=mono|c0=c${i}[a${audio_index}];"
                PROFIL_AUDIO_MAP+=(-map "[a${audio_index}]")
                audio_index=$((audio_index + 1))
            done
        fi
    done <<<"$ausgabe"

    if [ -n "$filter_complex" ]; then
        PROFIL_FILTER=(-filter_complex "${filter_complex%;}")
        PROFIL_VIDEO_MAP=(-map 0:0 -map 0:1)
    fi
    return 0
}

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
