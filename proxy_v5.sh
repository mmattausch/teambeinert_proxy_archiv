#!/usr/bin/env bash
# Proxy-Skript v5 – ersetzt proxy_conv_docker_v4.sh (Team Beinert, Strang PX, M-01)
#
# Erzeugt 540p-Schnittproxys wie v4: zentral unter <ZENTRAL>/<Pfad>/<Name>.<ext>.mov
# und neben dem Original unter <Ordner>/Proxies/<Name>.mov. ffmpeg-Parameter
# unverändert (lib/proxy_profil.sh). Neu ist alles um ffmpeg herum: kein eval,
# Teildatei mit Prüfung, Sperre, sauberer Abbruch, Protokoll.
#
# Aufrufe:
#   proxy_v5.sh                    Abendlauf auf ELSA (wie bisher der Cronjob)
#   proxy_v5.sh --datei <Datei>…   einzelne Dateien (z. B. per find | xargs -P 3)
#   proxy_v5.sh --lokal <Ordner>   Schnittrechner: Ordner abarbeiten, nur Proxies/ schreiben
#   proxy_v5.sh --nur-pruefen [<Ordner>]
#                                  vorhandene Proxys gegen das Original prüfen, nichts ändern
#   proxy_v5.sh --trocken [<Ordner>]
#                                  zeigen, was ein Lauf täte, nichts ändern
#   proxy_v5.sh --befehl <Datei>   ffmpeg-Aufruf für eine Datei anzeigen (Vergleich mit v4)
#
# Rückgabewert: 0 alles in Ordnung, 1 mindestens eine Datei mit Fehler,
#               2 Aufruf- oder Umgebungsfehler (nichts umgerechnet).

set -u
set -o pipefail
umask 0002

SKRIPT_VERSION="5.0.0-entwurf"

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    echo "Bash 4.4 oder neuer nötig (gefunden: ${BASH_VERSION:-?})." >&2
    exit 2
fi

SKRIPT="$(readlink -f -- "${BASH_SOURCE[0]}")"
SKRIPT_ORDNER="$(dirname -- "$SKRIPT")"
# shellcheck source=lib/kern.sh
source "$SKRIPT_ORDNER/lib/kern.sh"
# shellcheck source=lib/proxy_profil.sh
source "$SKRIPT_ORDNER/lib/proxy_profil.sh"

# ---------------------------------------------------------------------------
# Einstellungen (Standard: ELSA). Abweichungen in proxy_v5.konf neben dem Skript
# oder in der Datei, auf die PROXY_V5_KONF zeigt. Keine Geheimnisse darin.
# ---------------------------------------------------------------------------

AUFNAHMEN="/mnt/Aufnahme_mirror/Aufnahmen"
ZENTRAL="/mnt/Mirror_2x8TB/Proxy_Output/mnt/Aufnahmen"
PROTOKOLL_ORDNER="/mnt/Mirror_2x8TB/Proxy_Output/_protokolle"
FFMPEG_IMAGE="linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697"
CONTAINER_USER=""            # z. B. "<uid>:1003"; leer = Benutzer des Images
PARALLEL=3
ALTER_MIN=120                # Abendlauf: nur Dateien, die so lange unverändert sind
TOLERANZ_SEKUNDEN=1.0
RESERVE_BYTE=$((50 * 1024 * 1024 * 1024))
PROTOKOLL_AUFHEBEN_TAGE=90

konf="${PROXY_V5_KONF:-$SKRIPT_ORDNER/proxy_v5.konf}"
if [ -f "$konf" ]; then
    # shellcheck source=/dev/null
    source "$konf"
fi

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
# Eine Datei bearbeiten
#
# MODUS: elsa | lokal
# Ergebnis in ERGEBNIS (ok, kopiert, vorhanden, uebersprungen, kein_video, Fehler)
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

# Ergebnis festhalten. Im Abendlauf kommen "vorhanden" und "uebersprungen" nicht ins
# Protokoll (sonst jeden Abend tausende Zeilen); bei Einzelaufrufen alles.
ergebnis() {
    local wert="$1" grund="${2:-}" ziel="${3:-}"
    ERGEBNIS="$wert"
    zaehlen "$wert"
    case "$wert" in
        vorhanden | uebersprungen)
            [ "${LAUF_AKTIV:-0}" = "1" ] && return 0
            ;;
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

# Ziele berechnen: setzt ZIEL_LOKAL und ZIEL_ZENTRAL (ELSA) für $QUELLE
ziele_berechnen() {
    local ordner name stamm rel
    ordner="$(dirname -- "$QUELLE")"
    name="$(basename -- "$QUELLE")"
    stamm="${name%.*}"
    ZIEL_LOKAL="$ordner/Proxies/$stamm.mov"
    ZIEL_ZENTRAL=""
    if [ "$MODUS" = "elsa" ]; then
        rel="${ordner#"$AUFNAHMEN"}"
        rel="${rel#/}"
        ZIEL_ZENTRAL="$ZENTRAL/${rel:+$rel/}$name.mov"
    fi
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

    if ! platz_reicht "$(dirname -- "$ziel")" "$RESERVE_BYTE"; then
        ergebnis Fehler "zu wenig Platz in $(dirname -- "$ziel")"
        return
    fi

    local name="proxy_v5_$$_$RANDOM"
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

# Kopie eines vorhandenen Proxys an den anderen Ort (wie v4, über Teildatei)
kopieren() {
    local von="$1" nach="$2" rc
    G_QUELLE="$(groesse "$QUELLE")"
    AKTIV_TEIL="$nach.teil"
    kopieren_ueber_teil "$von" "$nach"
    rc=$?
    AKTIV_TEIL=""
    case "$rc" in
        0) G_ZIEL="$(groesse "$nach")"; ergebnis kopiert "aus $von" "$nach" ;;
        2) ergebnis vorhanden "" "$nach" ;;
        *) ergebnis Fehler "Kopieren nach $nach fehlgeschlagen" "$nach" ;;
    esac
}

datei_bearbeiten() {
    QUELLE="$(absolut "$1")"
    BEGINN="$(zeit)"
    ERGEBNIS=""
    TC=""
    G_QUELLE=""
    G_ZIEL=""
    unset q_ok q_laufzeit q_videospuren q_breite q_hoehe q_tonkanaele
    unset z_ok z_laufzeit z_videospuren z_breite z_hoehe z_tonkanaele

    local grund
    if [ ! -f "$QUELLE" ]; then
        ergebnis Fehler "Datei nicht gefunden"
        return
    fi
    if grund="$(ausgeschlossen)"; then
        ergebnis uebersprungen "$grund"
        return
    fi

    ziele_berechnen

    if ! sperre_holen "datei_$(schluessel "$ZIEL_LOKAL")"; then
        ergebnis uebersprungen "wird gerade von einem anderen Aufruf bearbeitet"
        return
    fi

    AKTIV_QUELLE="$QUELLE"
    AKTIV_BEGINN="$BEGINN"

    if [ "$MODUS" = "lokal" ]; then
        if [ -f "$ZIEL_LOKAL" ]; then
            ergebnis vorhanden "" "$ZIEL_LOKAL"
        else
            ordner_anlegen "$(dirname -- "$ZIEL_LOKAL")" || { ergebnis Fehler "Ordner Proxies/ nicht anlegbar"; AKTIV_QUELLE=""; return; }
            umrechnen "$ZIEL_LOKAL.teil" "$ZIEL_LOKAL"
            [ "$ERGEBNIS" = "ok" ] && ergebnis ok "" "$ZIEL_LOKAL"
        fi
        AKTIV_QUELLE=""
        return
    fi

    # ELSA: wie v4 – beide da: nichts; eine fehlt: kopieren; keine: umrechnen
    local hat_lokal=0 hat_zentral=0
    [ -f "$ZIEL_LOKAL" ] && hat_lokal=1
    [ -f "$ZIEL_ZENTRAL" ] && hat_zentral=1

    if [ "$hat_lokal" = 1 ] && [ "$hat_zentral" = 1 ]; then
        ergebnis vorhanden "" "$ZIEL_LOKAL"
    elif [ "$hat_lokal" = 1 ]; then
        kopieren "$ZIEL_LOKAL" "$ZIEL_ZENTRAL"
    elif [ "$hat_zentral" = 1 ]; then
        kopieren "$ZIEL_ZENTRAL" "$ZIEL_LOKAL"
    else
        if ! ordner_anlegen "$(dirname -- "$ZIEL_ZENTRAL")"; then
            ergebnis Fehler "Ordner in der zentralen Ablage nicht anlegbar"
        elif ! ordner_anlegen "$(dirname -- "$ZIEL_LOKAL")"; then
            ergebnis Fehler "Ordner Proxies/ nicht anlegbar"
        else
            umrechnen "$ZIEL_ZENTRAL.teil" "$ZIEL_ZENTRAL"
            if [ "$ERGEBNIS" = "ok" ]; then
                local g_zentral="$G_ZIEL"
                case "$(kopieren_ueber_teil "$ZIEL_ZENTRAL" "$ZIEL_LOKAL"; echo $?)" in
                    0 | 2) G_ZIEL="$g_zentral"; ergebnis ok "" "$ZIEL_ZENTRAL" ;;
                    *) ergebnis Fehler "Proxy erzeugt, Kopie nach Proxies/ fehlgeschlagen" "$ZIEL_ZENTRAL" ;;
                esac
            fi
        fi
    fi
    AKTIV_QUELLE=""
}

# ---------------------------------------------------------------------------
# Vorhandene Proxys prüfen (--nur-pruefen), ändert nichts
# ---------------------------------------------------------------------------

proxy_pruefen() {
    QUELLE="$(absolut "$1")"
    BEGINN="$(zeit)"
    TC=""
    G_QUELLE=""
    G_ZIEL=""
    local grund ziel geprueft=0
    if grund="$(ausgeschlossen)"; then
        zaehlen uebersprungen
        return
    fi
    ziele_berechnen
    medien_eigenschaften "$QUELLE" q
    G_QUELLE="$(groesse "$QUELLE")"
    for ziel in "$ZIEL_LOKAL" "$ZIEL_ZENTRAL"; do
        [ -n "$ziel" ] && [ -f "$ziel" ] || continue
        geprueft=1
        unset z_ok z_laufzeit z_videospuren z_breite z_hoehe z_tonkanaele
        G_ZIEL="$(groesse "$ziel")"
        if [ "$q_ok" != "1" ]; then
            ergebnis Fehler "ffprobe kann die Quelle nicht lesen" "$ziel"
            continue
        fi
        medien_eigenschaften "$ziel" z
        if grund="$(profil_pruefen "$TOLERANZ_SEKUNDEN" "$G_ZIEL")"; then
            ergebnis vorhanden_ok "" "$ziel"
        else
            ergebnis Fehler "$grund" "$ziel"
        fi
    done
    if [ "$geprueft" = 0 ]; then
        ergebnis Fehler "kein Proxy vorhanden"
    fi
}

# ---------------------------------------------------------------------------
# Trockenlauf (--trocken), ändert nichts
# ---------------------------------------------------------------------------

datei_trocken() {
    QUELLE="$(absolut "$1")"
    local grund
    if grund="$(ausgeschlossen)"; then
        printf 'überspringen  %s (%s)\n' "$QUELLE" "$grund"
        zaehlen uebersprungen
        return
    fi
    ziele_berechnen
    local hat_lokal=0 hat_zentral=0
    [ -f "$ZIEL_LOKAL" ] && hat_lokal=1
    [ -n "$ZIEL_ZENTRAL" ] && [ -f "$ZIEL_ZENTRAL" ] && hat_zentral=1
    if [ "$MODUS" = "lokal" ]; then
        if [ "$hat_lokal" = 1 ]; then zaehlen vorhanden; else printf 'umrechnen     %s\n' "$QUELLE"; zaehlen umrechnen; fi
        return
    fi
    if [ "$hat_lokal" = 1 ] && [ "$hat_zentral" = 1 ]; then
        zaehlen vorhanden
    elif [ "$hat_lokal" = 1 ]; then
        printf 'kopieren      %s -> %s\n' "$ZIEL_LOKAL" "$ZIEL_ZENTRAL"; zaehlen kopieren
    elif [ "$hat_zentral" = 1 ]; then
        printf 'kopieren      %s -> %s\n' "$ZIEL_ZENTRAL" "$ZIEL_LOKAL"; zaehlen kopieren
    else
        printf 'umrechnen     %s\n' "$QUELLE"; zaehlen umrechnen
    fi
}

# ---------------------------------------------------------------------------
# Dateien finden
# ---------------------------------------------------------------------------

# Alle Videodateien unter $1, NUL-getrennt. $2 = Mindestalter in Minuten (0 = alle).
# Auf ELSA werden Aufnahmen/00_* und Aufnahmen/01_* gar nicht erst betreten.
dateien_finden() {
    local wurzel="$1" alter="$2"
    local -a ausschluss=() alterfilter=()
    if [ "$MODUS" = "elsa" ] && [ "$wurzel" = "$AUFNAHMEN" ]; then
        ausschluss=(\( -path "$AUFNAHMEN/00_*" -o -path "$AUFNAHMEN/01_*" \) -prune -o)
    fi
    if [ "$alter" -gt 0 ]; then
        alterfilter=(-mmin "+$alter")
    fi
    find "$wurzel" "${ausschluss[@]}" -type d -name Proxies -prune -o \
        -type f ! -name '.*' \
        \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) \
        "${alterfilter[@]}" -print0
}

# ---------------------------------------------------------------------------
# Lauf über viele Dateien: ruft sich selbst je Datei auf (parallel, wie v4)
# ---------------------------------------------------------------------------

viele_dateien() {
    local aktion="$1" wurzel="$2" alter="$3" rc
    export LAUF_AKTIV=1 PROTOKOLL_DATEI ZAEHLER_DATEI MODUS AUFNAHMEN ZENTRAL PROTOKOLL_ORDNER \
        FFMPEG_IMAGE CONTAINER_USER TOLERANZ_SEKUNDEN RESERVE_BYTE SPERR_ORDNER LOKAL_WURZEL
    dateien_finden "$wurzel" "$alter" | xargs -0 -r -n 1 -P "$PARALLEL" "$SKRIPT" "--intern-$aktion"
    rc=$?
    case "$rc" in
        0 | 123) return 0 ;;
        *) warnung "xargs endete mit $rc"; return 2 ;;
    esac
}

# Rückgabewert aus der Zählerdatei
rueckgabe_aus_zaehler() {
    if [ -s "$ZAEHLER_DATEI" ] && grep -qx -e Fehler -e abgebrochen "$ZAEHLER_DATEI"; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Umgebung prüfen
# ---------------------------------------------------------------------------

umgebung_pruefen() {
    if ! command -v flock > /dev/null 2>&1; then
        echo "flock fehlt." >&2; return 2
    fi
    if ! im_container; then
        if ! docker image inspect "$FFMPEG_IMAGE" > /dev/null 2>&1; then
            echo "Image nicht vorhanden oder Docker nicht erreichbar: $FFMPEG_IMAGE" >&2
            echo "Es wird bewusst nichts automatisch geladen (feste Version)." >&2
            return 2
        fi
    fi
    return 0
}

einbindungen_setzen() {
    EINBINDUNGEN_LESEN=()
    EINBINDUNGEN_SCHREIBEN=()
    if [ "$MODUS" = "elsa" ]; then
        EINBINDUNGEN_LESEN=("$AUFNAHMEN")
        EINBINDUNGEN_SCHREIBEN=("$ZENTRAL")
    else
        EINBINDUNGEN_SCHREIBEN=("$LOKAL_WURZEL")
    fi
}

ordner_vorbereiten_elsa() {
    if [ ! -d "$AUFNAHMEN" ]; then
        echo "Aufnahmen nicht gefunden: $AUFNAHMEN" >&2; return 2
    fi
    if ! mkdir -p -- "$ZENTRAL" "$PROTOKOLL_ORDNER" 2>/dev/null || [ ! -w "$ZENTRAL" ] || [ ! -w "$PROTOKOLL_ORDNER" ]; then
        echo "Zentrale Ablage oder Protokollordner nicht beschreibbar: $ZENTRAL, $PROTOKOLL_ORDNER" >&2
        return 2
    fi
    SPERR_ORDNER="$PROTOKOLL_ORDNER/.sperren"
    return 0
}

hilfe() {
    sed -n '2,22p' "$SKRIPT" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Hauptteil
# ---------------------------------------------------------------------------

MODUS="${MODUS:-elsa}"
AUFTRAG=""
ERGEBNIS=""
LOKAL_WURZEL="${LOKAL_WURZEL:-}"
EINBINDUNGEN_LESEN=()
EINBINDUNGEN_SCHREIBEN=()
FFMPEG_BEFEHL=()

aufruf="${1:---lauf}"
[ $# -gt 0 ] && shift

case "$aufruf" in
    -h | --hilfe | --help)
        hilfe
        exit 0
        ;;

    --intern-datei | --intern-pruefen | --intern-trocken)
        # Von viele_dateien über xargs; Umgebung kommt per export
        einbindungen_setzen
        trap abbruch TERM INT HUP
        case "$aufruf" in
            --intern-datei) datei_bearbeiten "$1" ;;
            --intern-pruefen) proxy_pruefen "$1" ;;
            --intern-trocken) datei_trocken "$1" ;;
        esac
        [ "$ERGEBNIS" = "Fehler" ] && exit 1
        exit 0
        ;;

    --lauf)
        MODUS="elsa"
        umgebung_pruefen || exit 2
        ordner_vorbereiten_elsa || exit 2
        einbindungen_setzen
        if ! sperre_holen "lauf"; then
            meldung "Ein anderer Lauf ist noch aktiv; dieser endet ohne Arbeit."
            exit 2
        fi
        stempel="$(date '+%Y-%m-%d_%H%M%S')"
        PROTOKOLL_DATEI="$PROTOKOLL_ORDNER/lauf_$stempel.csv"
        ZAEHLER_DATEI="$PROTOKOLL_ORDNER/.zaehler_$stempel"
        : > "$ZAEHLER_DATEI"
        protokoll_beginnen || exit 2
        meldung "Proxy-Skript $SKRIPT_VERSION, Lauf über $AUFNAHMEN (älter als $ALTER_MIN Minuten, $PARALLEL parallel)"
        teilreste_loeschen "$ZENTRAL" '*.mov.teil'
        teilreste_loeschen "$AUFNAHMEN" '*/Proxies/*.mov.teil'
        viele_dateien datei "$AUFNAHMEN" "$ALTER_MIN"
        rc=$?
        zusammenfassung "$ZAEHLER_DATEI"
        rueckgabe_aus_zaehler
        rc2=$?
        rm -f -- "$ZAEHLER_DATEI"
        # Protokolle ohne Eintrag (nur Kopfzeile) nicht aufheben
        if [ "$(wc -l < "$PROTOKOLL_DATEI")" -le 1 ]; then rm -f -- "$PROTOKOLL_DATEI"; fi
        find "$PROTOKOLL_ORDNER" -maxdepth 1 -type f -name 'lauf_*.csv' -mtime "+$PROTOKOLL_AUFHEBEN_TAGE" -delete 2>/dev/null
        [ "$rc" -eq 2 ] && exit 2
        exit "$rc2"
        ;;

    --datei)
        MODUS="elsa"
        [ $# -ge 1 ] || { echo "Aufruf: $0 --datei <Datei> …" >&2; exit 2; }
        umgebung_pruefen || exit 2
        ordner_vorbereiten_elsa || exit 2
        einbindungen_setzen
        PROTOKOLL_DATEI="$PROTOKOLL_ORDNER/einzel_$(date '+%Y-%m-%d').csv"
        ZAEHLER_DATEI=""
        protokoll_beginnen || exit 2
        trap abbruch TERM INT HUP
        fehler=0
        for datei in "$@"; do
            datei_bearbeiten "$datei"
            [ "$ERGEBNIS" = "Fehler" ] && fehler=1
        done
        exit "$fehler"
        ;;

    --lokal)
        MODUS="lokal"
        [ $# -eq 1 ] && [ -d "$1" ] || { echo "Aufruf: $0 --lokal <Ordner>" >&2; exit 2; }
        LOKAL_WURZEL="$(cd -- "$1" && pwd)"
        umgebung_pruefen || exit 2
        einbindungen_setzen
        SPERR_ORDNER="${TMPDIR:-/tmp}/proxy_v5_sperren"
        PROTOKOLL_DATEI="${PROTOKOLL_DATEI:-}"
        ZAEHLER_DATEI="$(mktemp)"
        protokoll_beginnen || exit 2
        meldung "Proxy-Skript $SKRIPT_VERSION, Proxys für $LOKAL_WURZEL ($PARALLEL parallel)"
        teilreste_loeschen "$LOKAL_WURZEL" '*/Proxies/*.mov.teil'
        viele_dateien datei "$LOKAL_WURZEL" 0
        rc=$?
        zusammenfassung "$ZAEHLER_DATEI"
        rueckgabe_aus_zaehler
        rc2=$?
        rm -f -- "$ZAEHLER_DATEI"
        if [ "$rc" -eq 2 ]; then
            meldung "Fertig mit Fehlern in der Umgebung."
            exit 2
        elif [ "$rc2" -ne 0 ]; then
            meldung "Fertig, aber nicht alle Proxys erstellt (siehe FEHLER oben)."
        else
            meldung "Fertig, alle Proxys erstellt."
        fi
        exit "$rc2"
        ;;

    --nur-pruefen | --trocken)
        wurzel="${1:-}"
        if [ "${PROXY_V5_IM_CONTAINER:-0}" = "1" ] && [ -n "$wurzel" ]; then
            MODUS="lokal"
            LOKAL_WURZEL="$(cd -- "$wurzel" && pwd)"
        else
            MODUS="elsa"
            ordner_vorbereiten_elsa || exit 2
        fi
        umgebung_pruefen || exit 2
        einbindungen_setzen
        [ -n "$wurzel" ] || wurzel="$AUFNAHMEN"
        wurzel="$(cd -- "$wurzel" && pwd)" || exit 2
        ZAEHLER_DATEI="$(mktemp)"
        if [ "$aufruf" = "--nur-pruefen" ]; then
            if [ "$MODUS" = "elsa" ]; then
                PROTOKOLL_DATEI="$PROTOKOLL_ORDNER/pruefung_$(date '+%Y-%m-%d_%H%M%S').csv"
                protokoll_beginnen || exit 2
                meldung "Prüfe vorhandene Proxys unter $wurzel; Protokoll: $PROTOKOLL_DATEI"
            fi
            SPERR_ORDNER="${SPERR_ORDNER:-${TMPDIR:-/tmp}/proxy_v5_sperren}"
            viele_dateien pruefen "$wurzel" 0
        else
            SPERR_ORDNER="${SPERR_ORDNER:-${TMPDIR:-/tmp}/proxy_v5_sperren}"
            viele_dateien trocken "$wurzel" 0
        fi
        rc=$?
        zusammenfassung "$ZAEHLER_DATEI"
        rueckgabe_aus_zaehler
        rc2=$?
        rm -f -- "$ZAEHLER_DATEI"
        [ "$rc" -eq 2 ] && exit 2
        exit "$rc2"
        ;;

    --befehl)
        MODUS="elsa"
        [ $# -eq 1 ] || { echo "Aufruf: $0 --befehl <Datei>" >&2; exit 2; }
        umgebung_pruefen || exit 2
        einbindungen_setzen
        QUELLE="$(absolut "$1")"
        ziele_berechnen
        ffmpeg_befehl_bauen "$ZIEL_ZENTRAL.teil" "proxy_v5_beispiel" || exit 1
        if [ "${BEFEHL_ZEILENWEISE:-0}" = "1" ]; then
            printf '%s\0' "${FFMPEG_BEFEHL[@]}"
        else
            printf '%q ' "${FFMPEG_BEFEHL[@]}"
            printf '\n'
        fi
        exit 0
        ;;

    *)
        echo "Unbekannter Aufruf: $aufruf (Hilfe: $0 --hilfe)" >&2
        exit 2
        ;;
esac
