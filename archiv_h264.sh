#!/usr/bin/env bash
# Archivskript – neue Fassung von archiv_h264.sh (Team Beinert, Strang PX, M-39)
#
# Rechnet Aufnahmen in H.264-Archiv-Fassungen um, mit unveränderten ffmpeg-Parametern
# (lib/archiv_profil.sh). Ziel wie bisher:
#   Aufnahmen/00_to_Backup/h264_archiv/<Pfad relativ zu Aufnahmen>/<Name>.<ext>.mov
# Neu ist alles um ffmpeg herum (Änderungsliste M1–M15): Teildatei mit Prüfung,
# Rückgabewerte, Protokoll-CSV, Auftragsdatei, Prüflauf, Sperre, sauberer Abbruch.
# Originale werden nie verändert oder gelöscht.
#
# Aufrufe:
#   archiv_h264.sh <Datei>…                    einzelne Dateien (wie bisher, auch per find | xargs -P 3)
#   archiv_h264.sh --ordner <Ordner>           alle Videodateien eines Ordners (ersetzt find | xargs -P 3)
#   archiv_h264.sh --auftrag <Auftrag.txt>     Auftragsdatei des Werkzeugs „Bandarchiv“
#   archiv_h264.sh --nur-pruefen --auftrag <Auftrag.txt>
#   archiv_h264.sh --nur-pruefen <Datei>…      vorhandene Archiv-Fassungen prüfen, nichts umrechnen
#   archiv_h264.sh --befehl <Datei>            ffmpeg-Aufruf anzeigen (Vergleich mit dem alten Skript)
#
# Start langer Aufträge nur mit systemd-run --unit=archiv-<Auftrag> (Arbeitsregeln).
#
# Rückgabewert: 0 alle Dateien ok, vorhanden_ok, kein_video oder zulässig übersprungen,
#               1 mindestens eine Datei mit Fehler, 2 Aufruf- oder Umgebungsfehler.

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
# shellcheck source=lib/v4_gemeinsam.sh
source "$SKRIPT_ORDNER/lib/v4_gemeinsam.sh"
# shellcheck source=lib/ablauf.sh
source "$SKRIPT_ORDNER/lib/ablauf.sh"
# shellcheck source=lib/archiv_profil.sh
source "$SKRIPT_ORDNER/lib/archiv_profil.sh"

# ---------------------------------------------------------------------------
# Einstellungen (Standard: ELSA). Abweichungen in archiv_h264.konf neben dem Skript
# oder in der Datei, auf die ARCHIV_KONF zeigt. Keine Geheimnisse darin.
# ---------------------------------------------------------------------------

AUFNAHMEN="/mnt/Aufnahme_mirror/Aufnahmen"
ZIEL_WURZEL="/mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup/h264_archiv"
PROTOKOLL_ORDNER=""          # leer = <ZIEL_WURZEL>/_protokolle
FFMPEG_IMAGE="linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697"
CONTAINER_USER=""            # z. B. "<uid>:1003"; leer = Benutzer des Images
PARALLEL=3                   # wie der bisherige Aufruf mit xargs -P 3
TOLERANZ_SEKUNDEN=1.0        # TOLERANZ_SEKUNDEN aus M3
RESERVE_BYTE=$((50 * 1024 * 1024 * 1024))
AENDERUNGSZEIT_UEBERNEHMEN=0 # M16, noch offen: 1 = Archiv-Fassung bekommt die Änderungszeit des Originals
CONTAINER_PRAEFIX="archiv"

konf="${ARCHIV_KONF:-$SKRIPT_ORDNER/archiv_h264.konf}"
if [ -f "$konf" ]; then
    # shellcheck source=/dev/null
    source "$konf"
fi
[ -n "$PROTOKOLL_ORDNER" ] || PROTOKOLL_ORDNER="$ZIEL_WURZEL/_protokolle"

MODUS="elsa"
AUFTRAG="${AUFTRAG:-}"
ERGEBNIS=""
EINBINDUNGEN_LESEN=("$AUFNAHMEN")
EINBINDUNGEN_SCHREIBEN=("$ZIEL_WURZEL")
FFMPEG_BEFEHL=()
SPERR_ORDNER="$PROTOKOLL_ORDNER/.sperren"

# ---------------------------------------------------------------------------
# Eine Datei
# ---------------------------------------------------------------------------

ziel_berechnen() {
    local ordner name rel
    ordner="$(dirname -- "$QUELLE")"
    name="$(basename -- "$QUELLE")"
    rel="${ordner#"$AUFNAHMEN"}"
    rel="${rel#/}"
    ZIEL="$ZIEL_WURZEL/${rel:+$rel/}$name.mov"
}

datei_vorbereiten() {
    QUELLE="$(absolut "$1")"
    BEGINN="$(zeit)"
    ERGEBNIS=""
    TC=""
    G_QUELLE=""
    G_ZIEL=""
    ZIEL=""
    unset q_ok q_laufzeit q_videospuren q_breite q_hoehe q_tonkanaele
    unset z_ok z_laufzeit z_videospuren z_breite z_hoehe z_tonkanaele
}

# Vorhandene Archiv-Fassung gegen das Original prüfen (M3). Setzt ERGEBNIS.
vorhandene_pruefen() {
    local grund
    medien_eigenschaften "$QUELLE" q
    G_QUELLE="$(groesse "$QUELLE")"
    G_ZIEL="$(groesse "$ZIEL")"
    if [ "$q_ok" != "1" ]; then
        ergebnis Fehler "ffprobe kann die Quelle nicht lesen" "$ZIEL"
        return
    fi
    medien_eigenschaften "$ZIEL" z
    if grund="$(profil_pruefen "$TOLERANZ_SEKUNDEN" "$G_ZIEL")"; then
        ergebnis vorhanden_ok "" "$ZIEL"
    else
        ergebnis Fehler "vorhandene Archiv-Fassung besteht die Prüfung nicht: $grund" "$ZIEL"
    fi
}

datei_archivieren() {
    datei_vorbereiten "$1"
    local grund
    if [ ! -f "$QUELLE" ]; then
        ergebnis Fehler "Datei nicht gefunden"
        return
    fi
    if grund="$(ausgeschlossen)"; then
        ergebnis uebersprungen "$grund"
        return
    fi
    ziel_berechnen

    if ! sperre_holen "datei_$(schluessel "$ZIEL")"; then
        ergebnis Fehler "wird gerade von einem anderen Aufruf bearbeitet" "$ZIEL"
        return
    fi

    # Fortsetzen (M5): Vorhandene Archiv-Fassung nur übernehmen, wenn sie die Prüfung besteht
    if [ -f "$ZIEL" ]; then
        vorhandene_pruefen
        return
    fi

    if ! ordner_anlegen "$(dirname -- "$ZIEL")"; then
        ergebnis Fehler "Zielordner nicht anlegbar: $(dirname -- "$ZIEL")"
        return
    fi

    AKTIV_QUELLE="$QUELLE"
    AKTIV_BEGINN="$BEGINN"
    umrechnen "$ZIEL.teil" "$ZIEL"
    AKTIV_QUELLE=""
    if [ "$ERGEBNIS" = "ok" ]; then
        if [ "$AENDERUNGSZEIT_UEBERNEHMEN" = "1" ]; then
            touch -r "$QUELLE" -- "$ZIEL"
        fi
        ergebnis ok "" "$ZIEL"
    fi
}

# --nur-pruefen: nichts umrechnen, nichts löschen
datei_nur_pruefen() {
    datei_vorbereiten "$1"
    local grund
    if [ ! -f "$QUELLE" ]; then
        ergebnis Fehler "Datei nicht gefunden"
        return
    fi
    if grund="$(ausgeschlossen)"; then
        ergebnis uebersprungen "$grund"
        return
    fi
    ziel_berechnen
    if [ ! -f "$ZIEL" ]; then
        medien_eigenschaften "$QUELLE" q
        G_QUELLE="$(groesse "$QUELLE")"
        if [ "$q_ok" = "1" ] && [ "$q_videospuren" -lt 1 ]; then
            ergebnis kein_video "keine Videospur"
        else
            ergebnis Fehler "Archiv-Fassung fehlt" "$ZIEL"
        fi
        return
    fi
    vorhandene_pruefen
}

# ---------------------------------------------------------------------------
# Umgebung, Auftragsdatei
# ---------------------------------------------------------------------------

umgebung_pruefen() {
    if ! command -v flock > /dev/null 2>&1; then
        echo "flock fehlt." >&2; return 2
    fi
    if [ ! -d "$AUFNAHMEN" ]; then
        echo "Aufnahmen nicht gefunden: $AUFNAHMEN" >&2; return 2
    fi
    if ! mkdir -p -- "$ZIEL_WURZEL" "$PROTOKOLL_ORDNER" 2>/dev/null || [ ! -w "$ZIEL_WURZEL" ] || [ ! -w "$PROTOKOLL_ORDNER" ]; then
        echo "Zielordner oder Protokollordner nicht beschreibbar: $ZIEL_WURZEL, $PROTOKOLL_ORDNER" >&2
        return 2
    fi
    if ! docker image inspect "$FFMPEG_IMAGE" > /dev/null 2>&1; then
        echo "Image nicht vorhanden oder Docker nicht erreichbar: $FFMPEG_IMAGE" >&2
        echo "Es wird bewusst nichts automatisch geladen (feste Version)." >&2
        return 2
    fi
    return 0
}

# Auftragsdatei lesen (M5): UTF-8, je Zeile ein absoluter Pfad; Leerzeilen und #-Zeilen
# werden übersprungen. Ausgabe NUL-getrennt. Gelesen wird über einen eigenen Kanal,
# damit nichts in der Schleife die Standardeingabe verschluckt.
auftrag_lesen() {
    local datei="$1" zeile
    while IFS= read -r -u 3 zeile || [ -n "$zeile" ]; do
        zeile="${zeile%$'\r'}"
        case "$zeile" in
            "" | \#*) continue ;;
        esac
        printf '%s\0' "$zeile"
    done 3< "$datei"
}

# Viele Dateien parallel: ruft sich selbst je Datei auf
viele_dateien() {
    local aktion="$1" rc
    export AUFTRAG PROTOKOLL_DATEI ZAEHLER_DATEI AUFNAHMEN ZIEL_WURZEL PROTOKOLL_ORDNER \
        FFMPEG_IMAGE CONTAINER_USER TOLERANZ_SEKUNDEN RESERVE_BYTE AENDERUNGSZEIT_UEBERNEHMEN
    xargs -0 -r -n 1 -P "$PARALLEL" "$BASH" "$SKRIPT" "--intern-$aktion"
    rc=$?
    case "$rc" in
        0 | 123) return 0 ;;
        *) warnung "xargs endete mit $rc"; return 2 ;;
    esac
}

abschluss() {
    local rc="$1"
    zusammenfassung "$ZAEHLER_DATEI"
    rueckgabe_aus_zaehler
    local rc2=$?
    rm -f -- "$ZAEHLER_DATEI"
    [ "$rc" -eq 2 ] && return 2
    return "$rc2"
}

hilfe() {
    sed -n '2,24p' "$SKRIPT" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Hauptteil
# ---------------------------------------------------------------------------

nur_pruefen=0
if [ "${1:-}" = "--nur-pruefen" ]; then
    nur_pruefen=1
    shift
fi
aufruf="${1:-}"

case "$aufruf" in
    "" | -h | --hilfe | --help)
        hilfe
        [ -n "$aufruf" ] && exit 0
        exit 2
        ;;

    --intern-datei | --intern-pruefen)
        trap abbruch TERM INT HUP
        if [ "$aufruf" = "--intern-datei" ]; then
            datei_archivieren "$2"
        else
            datei_nur_pruefen "$2"
        fi
        [ "$ERGEBNIS" = "Fehler" ] && exit 1
        exit 0
        ;;

    --auftrag)
        auftragsdatei="${2:-}"
        if [ -z "$auftragsdatei" ] || [ ! -f "$auftragsdatei" ]; then
            echo "Auftragsdatei nicht gefunden: ${auftragsdatei:-<fehlt>}" >&2
            exit 2
        fi
        umgebung_pruefen || exit 2
        AUFTRAG="$(basename -- "$auftragsdatei")"
        AUFTRAG="${AUFTRAG%.txt}"
        if ! sperre_holen "auftrag"; then
            meldung "Ein anderer Auftrag läuft noch; dieser endet ohne Arbeit."
            exit 2
        fi
        PROTOKOLL_DATEI="$PROTOKOLL_ORDNER/$AUFTRAG.csv"
        ZAEHLER_DATEI="$(mktemp)"
        protokoll_beginnen || exit 2
        if [ "$nur_pruefen" = 1 ]; then
            meldung "Archivskript $SKRIPT_VERSION, Prüflauf für Auftrag $AUFTRAG (nichts wird umgerechnet)"
            auftrag_lesen "$auftragsdatei" | viele_dateien pruefen
        else
            meldung "Archivskript $SKRIPT_VERSION, Auftrag $AUFTRAG ($PARALLEL parallel), Ziel $ZIEL_WURZEL"
            teilreste_loeschen "$ZIEL_WURZEL" '*.mov.teil'
            auftrag_lesen "$auftragsdatei" | viele_dateien datei
        fi
        rc=$?
        meldung "Protokoll: $PROTOKOLL_DATEI"
        abschluss "$rc"
        exit $?
        ;;

    --ordner)
        # Alle Videodateien eines Ordners, wie bisher per find | xargs -P 3 (zusätzlicher Aufruf,
        # nicht in der Änderungsliste; Ergebnis wie Einzelaufrufe im Protokoll einzel_<Datum>.csv)
        ordner="${2:-}"
        if [ -z "$ordner" ] || [ ! -d "$ordner" ]; then
            echo "Ordner nicht gefunden: ${ordner:-<fehlt>}" >&2
            exit 2
        fi
        umgebung_pruefen || exit 2
        ordner="$(cd -- "$ordner" && pwd)"
        PROTOKOLL_DATEI="$PROTOKOLL_ORDNER/einzel_$(date '+%Y-%m-%d').csv"
        ZAEHLER_DATEI="$(mktemp)"
        protokoll_beginnen || exit 2
        meldung "Archivskript $SKRIPT_VERSION, Ordner $ordner ($PARALLEL parallel)"
        if [ "$nur_pruefen" = 1 ]; then aktion=pruefen; else aktion=datei; fi
        find "$ordner" -type d -name Proxies -prune -o -type f ! -name '.*' \
            \( -iname '*.mp4' -o -iname '*.mxf' -o -iname '*.mov' -o -iname '*.mpeg' -o -iname '*.avi' -o -iname '*.mts' \) \
            -print0 | viele_dateien "$aktion"
        rc=$?
        meldung "Protokoll: $PROTOKOLL_DATEI"
        abschluss "$rc"
        exit $?
        ;;

    --befehl)
        [ $# -eq 2 ] || { echo "Aufruf: $0 --befehl <Datei>" >&2; exit 2; }
        datei_vorbereiten "$2"
        ziel_berechnen
        ffmpeg_befehl_bauen "$ZIEL.teil" "archiv_beispiel" || exit 1
        if [ "${BEFEHL_ZEILENWEISE:-0}" = "1" ]; then
            printf '%s\0' "${FFMPEG_BEFEHL[@]}"
        else
            printf '%q ' "${FFMPEG_BEFEHL[@]}"
            printf '\n'
        fi
        exit 0
        ;;

    -*)
        echo "Unbekannter Aufruf: $aufruf (Hilfe: $0 --hilfe)" >&2
        exit 2
        ;;

    *)
        # Einzelne Dateien (bisheriger Aufruf)
        umgebung_pruefen || exit 2
        PROTOKOLL_DATEI="$PROTOKOLL_ORDNER/einzel_$(date '+%Y-%m-%d').csv"
        ZAEHLER_DATEI=""
        protokoll_beginnen || exit 2
        trap abbruch TERM INT HUP
        fehler=0
        for datei in "$@"; do
            if [ "$nur_pruefen" = 1 ]; then
                datei_nur_pruefen "$datei"
            else
                datei_archivieren "$datei"
            fi
            [ "$ERGEBNIS" = "Fehler" ] && fehler=1
        done
        exit "$fehler"
        ;;
esac
