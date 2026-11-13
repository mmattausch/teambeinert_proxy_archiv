# shellcheck shell=bash
# Gemeinsamer Kern für Proxy-Skript v5 und Archivskript.
#
# Wird von den Einstiegen (proxy_v5.sh, später archiv_h264.sh) per "source" geladen.
# Enthält nichts Profil-Spezifisches: keine ffmpeg-Parameter, keine Zielnamen.
#
# Grundsätze (CLAUDE.md):
# - Befehle nur als Bash-Array, nie eval, nie zusammengesetzte Strings.
# - Dateinamen sind nicht vertrauenswürdig.
# - Unter dem endgültigen Namen liegt nur, was geprüft ist (Teildatei .teil, dann mv -n).
# - Originale werden nie verändert oder gelöscht.

# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

zeit() { date '+%Y-%m-%d %H:%M:%S'; }

meldung() { printf '%s %s\n' "$(zeit)" "$*"; }

warnung() { printf '%s WARNUNG: %s\n' "$(zeit)" "$*" >&2; }

# ---------------------------------------------------------------------------
# Kleine Hilfen (GNU coreutils: ELSA, Container, Colima-VM für Tests)
# ---------------------------------------------------------------------------

groesse() { stat -c '%s' -- "$1" 2>/dev/null; }

aenderungszeit() { stat -c '%Y' -- "$1" 2>/dev/null; }

# Freier Platz in Byte auf dem Dateisystem, das den Pfad enthält
freier_platz() {
    df -Pk -- "$1" 2>/dev/null | awk 'NR == 2 { printf "%.0f\n", $4 * 1024 }'
}

# Kurzer, dateinamentauglicher Schlüssel für einen Pfad (für Sperren)
schluessel() {
    printf '%s' "$1" | cksum | awk '{ print $1 "_" $2 }'
}

ist_zahl() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Endung gehört zur Liste der Videoendungen (wie v4, Groß/klein egal)
ist_videoendung() {
    local endung="${1##*.}"
    [ "$endung" != "$1" ] || return 1
    endung="$(printf '%s' "$endung" | tr '[:upper:]' '[:lower:]')"
    case "$endung" in
        mp4 | mxf | mov | mpeg | avi | mts) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Container
#
# Auf ELSA (und bei Tests auf dem Mac) läuft das Skript auf dem Host und startet
# ffmpeg/ffprobe je Aufruf im Container. Am Schnittrechner läuft das ganze Skript
# schon im Container (proxy.bat setzt PROXY_V5_IM_CONTAINER=1); dann direkt aufrufen.
#
# Variablen (vom Einstieg gesetzt):
#   FFMPEG_IMAGE        Image mit festem Digest
#   CONTAINER_USER      leer oder "uid:gid" für docker run --user
#   EINBINDUNGEN_LESEN  Array: Pfade, nur lesend eingebunden
#   EINBINDUNGEN_SCHREIBEN  Array: Pfade, schreibbar eingebunden
# ---------------------------------------------------------------------------

im_container() { [ "${PROXY_V5_IM_CONTAINER:-0}" = "1" ]; }

# Baut die Anfangsargumente für einen Container-Aufruf in das Array, dessen Name
# in $1 steht. $2 = Programm im Container (ffmpeg oder ffprobe), $3 = Containername (darf leer sein).
container_vorspann() {
    local -n _ziel="$1"
    local programm="$2" name="${3:-}" p
    if im_container; then
        _ziel=("$programm")
        return
    fi
    _ziel=(docker run --rm)
    [ -n "$name" ] && _ziel+=(--name "$name")
    [ -n "${CONTAINER_USER:-}" ] && _ziel+=(--user "$CONTAINER_USER")
    for p in "${EINBINDUNGEN_LESEN[@]}"; do
        _ziel+=(-v "$p:$p:ro")
    done
    for p in "${EINBINDUNGEN_SCHREIBEN[@]}"; do
        _ziel+=(-v "$p:$p")
    done
    if [ "$programm" = "ffprobe" ]; then
        _ziel+=(--entrypoint ffprobe)
    fi
    _ziel+=("$FFMPEG_IMAGE")
}

# ffprobe mit festen Argumenten; Ausgabe auf stdout
ffprobe_lauf() {
    local -a cmd
    container_vorspann cmd ffprobe ""
    "${cmd[@]}" "$@" < /dev/null
}

# ---------------------------------------------------------------------------
# Eigenschaften einer Mediendatei
#
# medien_eigenschaften <Datei> <Präfix>
# setzt die Variablen <Präfix>_laufzeit, _videospuren, _breite, _hoehe (erste
# Videospur), _tonkanaele (Summe) und <Präfix>_ok (1 = lesbar).
# ---------------------------------------------------------------------------

medien_eigenschaften() {
    local datei="$1" praefix="$2" ausgabe zeile kanaele breite hoehe
    local laufzeit="" videospuren=0 b1="" h1="" summe=0 ok=0
    # Abschnittsnamen mitschreiben (compact, p=1): Bei MPEG-TS listet ffprobe dieselben
    # Spuren zusätzlich unter "program|stream|…"; gezählt werden nur Zeilen "stream|…".
    if ausgabe="$(ffprobe_lauf -v error \
        -show_entries 'format=duration:stream=codec_type,width,height,channels' \
        -of 'compact=p=1:nk=0' "$datei" 2>/dev/null)"; then
        ok=1
        while IFS= read -r zeile; do
            case "$zeile" in
                format\|*duration=*)
                    laufzeit="${zeile##*duration=}"
                    laufzeit="${laufzeit%%|*}"
                    ;;
                stream\|*codec_type=video*)
                    videospuren=$((videospuren + 1))
                    breite="$(sed -n 's/.*width=\([0-9]*\).*/\1/p' <<<"$zeile")"
                    hoehe="$(sed -n 's/.*height=\([0-9]*\).*/\1/p' <<<"$zeile")"
                    if [ -z "$b1" ]; then b1="$breite"; h1="$hoehe"; fi
                    ;;
                stream\|*codec_type=audio*)
                    kanaele="$(sed -n 's/.*channels=\([0-9]*\).*/\1/p' <<<"$zeile")"
                    ist_zahl "${kanaele:-x}" && summe=$((summe + kanaele))
                    ;;
            esac
        done <<<"$ausgabe"
    fi
    printf -v "${praefix}_ok" '%s' "$ok"
    printf -v "${praefix}_laufzeit" '%s' "$laufzeit"
    printf -v "${praefix}_videospuren" '%s' "$videospuren"
    printf -v "${praefix}_breite" '%s' "$b1"
    printf -v "${praefix}_hoehe" '%s' "$h1"
    printf -v "${praefix}_tonkanaele" '%s' "$summe"
}

# Laufzeitvergleich mit Toleranz (Sekunden, Kommazahlen)
laufzeit_passt() {
    awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN {
        if (a == "" || b == "" || a == "N/A" || b == "N/A") exit 1
        d = a - b; if (d < 0) d = -d
        exit (d <= t) ? 0 : 1
    }'
}

laufzeit_abweichung() {
    awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; printf "%.2f", d }' | tr '.' ','
}

# ---------------------------------------------------------------------------
# Protokoll (CSV nach Änderungsliste M4)
#
# PROTOKOLL_DATEI leer = kein CSV (z. B. am Schnittrechner).
# Jede Zeile wird mit einem einzigen printf angehängt; parallele Aufrufe
# schreiben so keine verschränkten Zeilen.
# ---------------------------------------------------------------------------

CSV_SPALTEN=(auftrag quelle ziel ergebnis meldung groesse_quelle groesse_ziel
    laufzeit_quelle laufzeit_ziel aufloesung_quelle aufloesung_ziel
    videospuren_quelle videospuren_ziel tonkanaele_quelle tonkanaele_ziel
    timecode beginn ende profil ffmpeg_image skript_version)

csv_feld() {
    local f="$1"
    if [[ "$f" == *[\;\"\ $'\n'$'\r']* ]]; then
        f="${f//\"/\"\"}"
        printf '"%s"' "$f"
    else
        printf '%s' "$f"
    fi
}

csv_zeile() {
    local zeile="" feld erster=1
    for feld in "$@"; do
        if [ "$erster" -eq 1 ]; then erster=0; else zeile+=";"; fi
        zeile+="$(csv_feld "$feld")"
    done
    printf '%s\n' "$zeile"
}

protokoll_beginnen() {
    [ -n "${PROTOKOLL_DATEI:-}" ] || return 0
    mkdir -p -- "$(dirname -- "$PROTOKOLL_DATEI")" || return 1
    if [ ! -s "$PROTOKOLL_DATEI" ]; then
        csv_zeile "${CSV_SPALTEN[@]}" >> "$PROTOKOLL_DATEI"
    fi
}

# protokoll <Werte in der Reihenfolge von CSV_SPALTEN>
protokoll() {
    [ -n "${PROTOKOLL_DATEI:-}" ] || return 0
    local zeile
    zeile="$(csv_zeile "$@")"
    printf '%s\n' "$zeile" >> "$PROTOKOLL_DATEI"
}

# Ergebnis zusätzlich für die Zusammenfassung zählen (eine Zeile je Datei)
zaehlen() {
    [ -n "${ZAEHLER_DATEI:-}" ] || return 0
    printf '%s\n' "$1" >> "$ZAEHLER_DATEI"
}

zusammenfassung() {
    local datei="$1"
    [ -s "$datei" ] || { meldung "Zusammenfassung: keine Dateien bearbeitet."; return; }
    meldung "Zusammenfassung:"
    sort "$datei" | uniq -c | while read -r anzahl wert; do
        printf '    %-14s %6d\n' "$wert" "$anzahl"
    done
}

# ---------------------------------------------------------------------------
# Sperren (Änderungsliste M13)
#
# sperre_holen <Name>  -> 0 = gehalten, 1 = belegt
# Mit flock (ELSA, Container, Colima-VM für Tests). Die Sperre gilt bis zum Ende
# des Prozesses; der Kernel gibt sie auch nach einem Absturz frei.
# ---------------------------------------------------------------------------

sperre_holen() {
    local fd
    mkdir -p -- "$SPERR_ORDNER" || return 1
    exec {fd}>> "$SPERR_ORDNER/$1.sperre" || return 1
    if flock -n "$fd"; then
        return 0
    fi
    exec {fd}>&-
    return 1
}

# ---------------------------------------------------------------------------
# Ablage
# ---------------------------------------------------------------------------

# Ordner anlegen. umask 0002 im Einstieg: Gruppe darf schreiben; das setgid-Bit
# erbt Linux vom übergeordneten Ordner (Aufnahmen hat 2775).
ordner_anlegen() {
    [ -d "$1" ] && return 0
    mkdir -p -- "$1"
}

# Genug Platz? $1 = Pfad im Ziel-Dataset, $2 = Reserve in Byte
platz_reicht() {
    local frei
    frei="$(freier_platz "$1")"
    ist_zahl "${frei:-x}" || return 0
    [ "$frei" -ge "$2" ]
}

# Teildatei unter den endgültigen Namen bringen, ohne zu überschreiben.
# 0 = umbenannt, 1 = Ziel existierte schon (Teildatei wird gelöscht)
teildatei_uebernehmen() {
    local teil="$1" ziel="$2"
    if [ -e "$ziel" ]; then
        rm -f -- "$teil"
        return 1
    fi
    mv -n -- "$teil" "$ziel"
    if [ -e "$teil" ]; then
        rm -f -- "$teil"
        return 1
    fi
    return 0
}

# Kopie über Teildatei. 0 = ok, 1 = Fehler, 2 = Ziel existierte schon
kopieren_ueber_teil() {
    local quelle="$1" ziel="$2" teil="$2.teil"
    ordner_anlegen "$(dirname -- "$ziel")" || return 1
    rm -f -- "$teil"
    if ! cp -- "$quelle" "$teil"; then
        rm -f -- "$teil"
        return 1
    fi
    if [ "$(groesse "$teil")" != "$(groesse "$quelle")" ]; then
        rm -f -- "$teil"
        return 1
    fi
    teildatei_uebernehmen "$teil" "$ziel" || return 2
    return 0
}

# Reste abgebrochener Läufe löschen: nur eigene Teildateien, die seit mindestens
# 60 Minuten nicht mehr wachsen (ein laufender Aufruf schreibt ständig).
# $1 = Wurzel, $2 = Muster für find -path (z. B. '*/Proxies/*.mov.teil')
teilreste_loeschen() {
    local wurzel="$1" muster="$2" anzahl
    [ -d "$wurzel" ] || return 0
    anzahl="$(find "$wurzel" -type f -path "$muster" -mmin +60 -print -delete 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${anzahl:-0}" -gt 0 ]; then
        meldung "Reste abgebrochener Läufe gelöscht: $anzahl Teildatei(en) unter $wurzel"
    fi
    return 0
}
