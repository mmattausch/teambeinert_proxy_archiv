# shellcheck shell=bash
# Gemeinsamer Ablauf je Datei für Proxy-Skript v5 und Archivskript:
# Abbruch, Protokollzeile, Ausschlüsse, Umrechnen mit Teildatei und Prüfung.
#
# Erwartet vom Einstieg: PROFIL_KENNUNG, FFMPEG_IMAGE, SKRIPT_VERSION, AUFNAHMEN, MODUS,
# TOLERANZ_SEKUNDEN, CONTAINER_PRAEFIX und vom Profil die Funktionen
# profil_ffmpeg_argumente, profil_pruefen, profil_platzbedarf.

# ---------------------------------------------------------------------------
# Zustand für Abbruch
# ---------------------------------------------------------------------------

AKTIV_CONTAINER=""
AKTIV_PID=""
AKTIV_TEIL=""
AKTIV_QUELLE=""
AKTIV_BEGINN=""

abbruch() {
    trap - TERM INT HUP
    if [ -n "$AKTIV_CONTAINER" ]; then
        docker stop -t 5 "$AKTIV_CONTAINER" > /dev/null 2>&1
    fi
    if [ -n "$AKTIV_PID" ]; then
        kill "$AKTIV_PID" 2>/dev/null
        wait "$AKTIV_PID" 2>/dev/null
    fi
    if [ -n "$AKTIV_TEIL" ]; then
        rm -f -- "$AKTIV_TEIL"
    fi
    if [ -n "$AKTIV_QUELLE" ]; then
        meldung "Abgebrochen: $AKTIV_QUELLE"
        protokoll "${AUFTRAG:-}" "$AKTIV_QUELLE" "" "Fehler" "abgebrochen" "" "" "" "" "" "" "" "" "" "" "" \
            "$AKTIV_BEGINN" "$(zeit)" "$PROFIL_KENNUNG" "$FFMPEG_IMAGE" "$SKRIPT_VERSION"
        zaehlen "abgebrochen"
    fi
    exit 1
}

# ---------------------------------------------------------------------------
# Eine Datei: Protokoll, Ausschlüsse, Umrechnen
#
# MODUS: elsa | lokal
# Ergebnis in ERGEBNIS
# ---------------------------------------------------------------------------

# Protokollzeile für die aktuelle Datei. Felder, die nicht gesetzt sind, bleiben leer.
datei_protokoll() {
    local ergebnis="$1" grund="$2" ziel="${3:-}"
    local aufl_q="" aufl_z=""
    [ -n "${q_breite:-}" ] && aufl_q="${q_breite}x${q_hoehe}"
    [ -n "${z_breite:-}" ] && aufl_z="${z_breite}x${z_hoehe}"
    protokoll "${AUFTRAG:-}" "$QUELLE" "$ziel" "$ergebnis" "$grund" \
        "${G_QUELLE:-}" "${G_ZIEL:-}" "${q_laufzeit:-}" "${z_laufzeit:-}" "$aufl_q" "$aufl_z" \
        "${q_videospuren:-}" "${z_videospuren:-}" "${q_tonkanaele:-}" "${z_tonkanaele:-}" \
        "${TC:-}" "$BEGINN" "$(zeit)" "$PROFIL_KENNUNG" "$FFMPEG_IMAGE" "$SKRIPT_VERSION"
}

# Ergebnis festhalten. Ergebnisse in LEISE_ERGEBNISSE (Leerzeichen-getrennt) werden nur
# gezählt, nicht gemeldet und nicht protokolliert (Abendlauf: "vorhanden uebersprungen",
# sonst jeden Abend tausende Zeilen).
ergebnis() {
    local wert="$1" grund="${2:-}" ziel="${3:-}"
    ERGEBNIS="$wert"
    zaehlen "$wert"
    case " ${LEISE_ERGEBNISSE:-} " in
        *" $wert "*) return 0 ;;
    esac
    case "$wert" in
        Fehler) meldung "FEHLER: $QUELLE: $grund" ;;
        ok | kopiert | kein_video) meldung "$wert: $QUELLE${grund:+ ($grund)}" ;;
        *) meldung "$wert: $QUELLE${grund:+ ($grund)}" ;;
    esac
    datei_protokoll "$wert" "$grund" "$ziel"
}

# Pfad absolut machen, ohne Symlinks aufzulösen
absolut() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$(pwd)" "$1" ;;
    esac
}

# Prüft, ob die Datei überhaupt bearbeitet wird. Gibt den Grund aus, wenn nicht.
ausgeschlossen() {
    local name rel erster
    name="$(basename -- "$QUELLE")"
    case "$name" in
        .*) echo "versteckte Datei"; return 0 ;;
    esac
    if ! ist_videoendung "$name"; then
        echo "keine Videoendung"; return 0
    fi
    case "$QUELLE" in
        */Proxies/*) echo "liegt in Proxies/"; return 0 ;;
    esac
    if [ "$MODUS" = "elsa" ]; then
        case "$QUELLE" in
            "$AUFNAHMEN"/*) ;;
            *) echo "liegt nicht unter $AUFNAHMEN"; return 0 ;;
        esac
        rel="${QUELLE#"$AUFNAHMEN"/}"
        erster="${rel%%/*}"
        if [ "$erster" != "$rel" ]; then
            case "$erster" in
                00_* | 01_*) echo "liegt in $erster"; return 0 ;;
            esac
        fi
    fi
    return 1
}

# Vollständigen ffmpeg-Aufruf in FFMPEG_BEFEHL bauen (für Umrechnung und --befehl).
# Zusätzlich zu den Profil-Argumenten nur -hide_banner -loglevel error (Ausgabe kürzer,
# kein Einfluss auf die Datei).
ffmpeg_befehl_bauen() {
    local teil="$1" name="$2"
    TC="$(profil_timecode "$QUELLE")"
    profil_ton_zuordnung "$QUELLE" || return 1
    profil_ffmpeg_argumente "$QUELLE" "$TC" "$teil"
    container_vorspann FFMPEG_BEFEHL ffmpeg "$name"
    FFMPEG_BEFEHL+=(-hide_banner -loglevel error "${PROFIL_ARGS[@]}")
}

# Umrechnen in $1 (Teildatei), prüfen, unter $2 ablegen. Setzt ERGEBNIS über ergebnis().
umrechnen() {
    local teil="$1" ziel="$2" rc grund g_vorher m_vorher

    medien_eigenschaften "$QUELLE" q
    G_QUELLE="$(groesse "$QUELLE")"
    if [ "$q_ok" != "1" ]; then
        ergebnis Fehler "ffprobe kann die Quelle nicht lesen"
        return
    fi
    if [ "$q_videospuren" -lt 1 ]; then
        ergebnis kein_video "keine Videospur"
        return
    fi

    if ! platz_reicht "$(dirname -- "$ziel")" "$(profil_platzbedarf)"; then
        ergebnis Fehler "zu wenig Platz in $(dirname -- "$ziel")"
        return
    fi

    local name="${CONTAINER_PRAEFIX}_$$_$RANDOM"
    if ! ffmpeg_befehl_bauen "$teil" "$name"; then
        ergebnis Fehler "ffprobe für die Tonspuren fehlgeschlagen"
        return
    fi

    g_vorher="$G_QUELLE"
    m_vorher="$(aenderungszeit "$QUELLE")"

    AKTIV_CONTAINER="$name"
    im_container && AKTIV_CONTAINER=""
    rm -f -- "$teil"
    AKTIV_TEIL="$teil"
    "${FFMPEG_BEFEHL[@]}" < /dev/null &
    AKTIV_PID=$!
    wait "$AKTIV_PID"
    rc=$?
    AKTIV_PID=""
    AKTIV_CONTAINER=""

    if [ "$rc" -ne 0 ]; then
        rm -f -- "$teil"; AKTIV_TEIL=""
        ergebnis Fehler "ffmpeg Rückgabewert $rc"
        return
    fi

    G_ZIEL="$(groesse "$teil")"
    medien_eigenschaften "$teil" z
    if ! grund="$(profil_pruefen "$TOLERANZ_SEKUNDEN" "$G_ZIEL")"; then
        rm -f -- "$teil"; AKTIV_TEIL=""
        ergebnis Fehler "$grund"
        return
    fi

    if [ "$(groesse "$QUELLE")" != "$g_vorher" ] || [ "$(aenderungszeit "$QUELLE")" != "$m_vorher" ]; then
        rm -f -- "$teil"; AKTIV_TEIL=""
        ergebnis Fehler "Quelle hat sich während der Umrechnung verändert"
        return
    fi

    if ! teildatei_uebernehmen "$teil" "$ziel"; then
        AKTIV_TEIL=""
        ergebnis vorhanden "inzwischen von anderem Aufruf angelegt" "$ziel"
        return
    fi
    AKTIV_TEIL=""
    ERGEBNIS="ok"
}

# Rückgabewert aus der Zählerdatei
rueckgabe_aus_zaehler() {
    if [ -s "$ZAEHLER_DATEI" ] && grep -qx -e Fehler -e abgebrochen "$ZAEHLER_DATEI"; then
        return 1
    fi
    return 0
}

