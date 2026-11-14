# shellcheck shell=bash
# Timecode und Ton-Zuordnung, wie sie proxy_conv_docker_v4.sh und archiv_h264.sh
# übereinstimmend machen (Zeile für Zeile verglichen am 11.11.2026, siehe
# phase0/auswertung.md). Gilt für Proxy- und Archiv-Profil.
#
# Setzt PROFIL_FILTER, PROFIL_VIDEO_MAP, PROFIL_AUDIO_MAP (Ton) bzw. gibt den Timecode aus.

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

