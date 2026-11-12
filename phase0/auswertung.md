# Phase 0: Auswertung ELSA

Stand: 11.11.2026 · Messung auf ELSA am 11.11.2026, 22:41–22:45 (Block A und B aus `README.md`). Rohdaten in `phase0/ergebnisse/` (nicht im Repository, enthalten Projektnamen).

Einträge aus `Aufnahmen/00_PRIVAT` wurden aus den lokalen Listen entfernt und nicht ausgewertet.

## Noch offen

- Schnittrechner (README, Abschnitt D): Fragen, Messung Altersgrenze, Testlauf Docker unter Windows.

## Ergebnisse

| Thema | Befund | Folge für den Plan |
|---|---|---|
| v4 | `sha256` gleich der Kopie im Wissens-Repo (`36e29763…`). Datei vom 09.01.2026. | Ist-Stand bestätigt. |
| Image | `linuxserver/ffmpeg:latest`, Digest `sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697`, Image-ID `67645d14b8e6`, gebaut 17.10.2025, **ffmpeg 8.0**, libx264, libx265, libfdk_aac. | Diesen Digest für v5 und das Archiv festschreiben (M8). |
| Werkzeuge im Image | Bash 5.2, GNU find/xargs 4.9, flock (util-linux 2.39), coreutils 9.4, shuf, awk, sed, grep. Entrypoint `/ffmpegwrapper.sh`, kein Benutzer gesetzt (root). | **Weg A ist auf ELSA-Seite machbar.** Offen ist nur noch der Laufwerkszugriff unter Windows. |
| Python auf dem Host | 3.11.9 | Weg B wäre ebenfalls machbar. |
| Videodateien | 14.356 Dateien, ca. 27,2 TB, ohne `00_*`, `01_*`, `Proxies/`: mp4 12.830 (13,4 TB), mov 1.122 (13,3 TB), mxf 400 (0,5 TB), mts 4. **Keine** avi, mpeg. | Endungsliste bleibt (Gleichheit), avi/mpeg kommen derzeit nicht vor. |
| Ausgeschlossene Ordner | `00_to_Backup` 8.061 Videodateien, `00_to_restore` 1.697, `00_PRIVAT`, `00_Alte_Master_Rolf` 48. Kein `01_*` mit Videos. | **Der Rücksicherungsordner heißt `00_to_restore`** (von Michl bestätigt, im Wissens-Repo korrigiert). Für v5 egal (`00_*` wird übersprungen). |
| Dateien im Wurzelordner `Aufnahmen` | keine Videodateien (nur Skripte, Verknüpfungen, Systemdateien) | Befund 6 tritt nicht auf. |
| Gleicher Name, verschiedene Videoendungen | **0 Fälle** | Befund 5 tritt nicht auf. |
| Platz `Proxies/` | **249 GB** in `Aufnahme_mirror` (18.864 Dateien in `Proxies/`, inkl. `00_*`) | Schwachstelle (f) ist klein; kein Handlungsbedarf für v5. |
| Platz | `Aufnahme_mirror/Aufnahmen` 86 % belegt, 5,8 TB frei. `Proxy_Output` 32 %, 4,8 TB frei. | M14 bleibt Pflicht, besonders fürs Archiv. |
| `h264_archiv` | 646 Dateien, 1.072 GB | Umfang für `--nur-pruefen`: rund 650 ffprobe-Paare, Minuten, keine Stunden. |
| Rechte `Aufnahmen` | Dataset mit **POSIX-ACL** (`acltype posix`, `aclmode discard`), `mmattausch:Firma`, `2775`. Ebenso `00_to_Backup` und `h264_archiv`. | `mkdir -m 2775` funktioniert hier (M9). Die NFSv4-Einschränkung aus den Arbeitsregeln gilt für dieses Dataset nicht. |
| Rechte `Proxies/` heute | Ordner `root:Firma 2777`, Proxys `root:Firma`, Modus `rw-r-xr--` | Kollegen können Proxys löschen (Ordner beschreibbar), aber nicht überschreiben. Mit `--user` und `2775` wird das sauberer. |
| Rechte `Proxy_Output` | NFSv4-ACL (`aclmode passthrough`), `Proxy_Output` `777`, `mnt/Aufnahmen` `770`, Gruppe `Firma` erbt Vollzugriff. | Container-Benutzer muss in `Firma` sein. |
| Groß-/Kleinschreibung | beide Datasets `casesensitivity sensitive` | Für Kollegen am Mac/Windows über SMB trotzdem unauffällig, da keine Namenspaare. |
| Laufzeit v4 | letzter Lauf 20:00–20:12, Log 2,9 MB, am Ende nur Zeilen „übersprungen“. Die Dateisuche allein dauert ca. 15 s. | Die 12 Minuten entstehen durch das Starten von Skript und `grep` je Datei, nicht durch die Suche. Ein einzelner Lauf, der selbst sucht (v5), braucht Sekunden, wenn nichts zu tun ist. Zustandsführung ist nicht nötig. |

## Stichprobe: 100 zufällige Videodateien

| Aufbau | Anzahl | Typische Quelle |
|---|---:|---|
| 1 Video, 1 Tonspur stereo | 45 | vor allem Sony FX3 |
| 1 Video, 4 Tonspuren mono | 30 | Sony FX3 mit 4 Kanälen |
| **2 Videospuren** (1080p + 176p), 1 Tonspur mono | 18 | Überwachungskameras `DSCF*.MP4` |
| **2 Videospuren** (Video + MJPEG-Vorschaubild), **kein Ton** | 5 | DJI-Drohnen (ProRes 4:2:2 10 Bit bzw. H.264 10 Bit) |
| 1 Video, 1 Tonspur mono | 2 | Teams-Aufzeichnungen |

- **Keine** Datei mit mehr als 8 Kanälen oder mit 3/5/7 Kanälen. Die Befunde 1 und 2 sind in der Stichprobe nicht aufgetreten; ganz auszuschließen sind sie nicht (Rekorder, MXF).
- Videoformate: H.265 4:2:2 10 Bit 2160p (52), H.264 4:2:0 1080p (21 + 18 Überwachung), H.264 4:2:2 10 Bit (8), ProRes 422 2160p (4), H.265 4:2:0 10 Bit (7). Kein Interlaced-Material in der Stichprobe.
- **Timecode:** Wo die Datei einen Timecode trägt, liest v4 genau diesen (keine Abweichung). 27 Dateien ohne Timecode (Überwachung, Drohnen, Telefon, Teams) → `00:00:00:00`.

## Neuer Befund 8: zweite Videospur

v4 setzt bei Dateien mit Ton `-map 0:v`. Das nimmt **alle** Videospuren. Bei den Überwachungskameras wird die 176-Pixel-Spur also mit `scale=-1:540` hochgerechnet und als zweite Videospur in den Proxy geschrieben. Bei Dateien ohne Ton (Drohnen) bleibt `video_map` leer; ffmpeg wählt selbst eine Videospur, das Vorschaubild fällt weg.

**Bestätigt am 11.11.2026** an `…/Ueberwachungskamera/CAM1/101MEDIA/DSCF0180.MP4` (ffprobe auf ELSA):

| | Spuren | Laufzeit |
|---|---|---|
| Original | Video 1920×1080, Video 320×176, AAC | 10,31 s |
| Proxy `Proxies/DSCF0180.mov` | Video 960×540, **Video 982×540**, AAC, 2 Datenspuren | 10,32 s |
| Proxy zentral `DSCF0180.MP4.mov` | identisch mit dem lokalen | 10,32 s |

- Die Vorschauspur wird von 320×176 auf 982×540 hochgerechnet und als zweite Videospur geschrieben.
- Je Videospur eine Timecode-Datenspur (`tmcd`, entsteht durch `-timecode` im mov-Container).
- Laufzeit weicht um 0,01 s ab, weit innerhalb der Toleranz von M3.

Für v5.0 bleibt es wie in v4 (Gleichheit). Folge für die Prüfung M3: Die Zahl der Videospuren im Proxy ist nicht immer 1. Geprüft wird deshalb „gleich wie die Zuordnung von v4 sie ergibt“, nicht „gleich wie im Original“. Datenspuren zählen nicht mit.

## `archiv_h264.sh` im Ist-Stand

Datei vom 09.01.2026, 7.338 Byte, `truenas_admin:Firma`, `rwxrwx---`. Ist-Fassung im Wissens-Repo unter `docs/referenz/archiv_h264.IST-STAND.sh.txt`.

**Das Archivskript ist eine Abwandlung von v4.** Zeile für Zeile verglichen:

| Teil | gegenüber v4 |
|---|---|
| Timecode (ffmpeg-Ausgabe, erster Treffer) | **identisch** |
| Ton-Logik (bis 8 Kanäle `-map 0:a`/`-map 0:v`, sonst Monospuren, `-map 0:0 -map 0:1`) | **identisch**, einschließlich der Befunde 1, 2, 3 und 8 |
| Ausschluss `01_` (erster Ordner) und `/Proxies/` | identisch |
| Ausschluss `00_` | **anders:** `case "$1" in *"00_"*)` trifft `00_` an beliebiger Stelle (Änderungsliste M7) |
| Ziel | `00_to_Backup/h264_archiv/<Pfad>/<Name>.<ext>.mov`, nur ein Ziel, keine `Proxies/`-Kopie |
| Vorhandenes Ziel | existiert → Ende, ohne Prüfung |
| `mkdir -m 777`, `docker run -i -v /mnt:/mnt` ohne feste Version, `eval`, `exit 0` | identisch |
| ffmpeg | `-pix_fmt yuv420p10le -timecode … -c:v libx264 -c:a aac -preset veryfast -tune fastdecode -crf 18 -threads 4 -x264opts keyint=75`; **ohne** `-vf scale`, **ohne** `-profile:v main -level 2.1` |

**Folge:** Der gemeinsame Kern ist am Code bestätigt. Proxy und Archiv unterscheiden sich nur in den ffmpeg-Argumenten, im Ziel, in der Behandlung vorhandener Ziele und in der `00_`-Regel. Die Reihenfolge der Argumente ist bei beiden gleich (`-i`, [`-vf`], `-pix_fmt`, `-timecode`, Filter, Video-Zuordnung, Ton-Zuordnung, Codecs, [Profil/Level], Preset …), sodass ein Profil nur die Platzhalter füllt.

**Befund 9 (`00_` an beliebiger Stelle) gemessen:** 77 Videodateien mit zusammen **171 GB** in `Aufnahmen` enthalten `00_` im Pfad, ohne in einem `00_*`-Ordner zu liegen. Fast alle sind Telefonvideos nach dem Muster `VID_JJJJMMTT_hhmmss_…` (z. B. Uhrzeit `…1200_…`). Das heutige Archivskript überspringt sie still; nach Löschen der Originale wären sie weder umgerechnet noch auf Band. M7 behebt das; im Protokoll erscheinen sie künftig als umgerechnet.

## Schnittrechner VFX-WORKSTATION (Erhebung 12.11.2026, 08:34)

| Thema | Befund | Folge |
|---|---|---|
| System | Windows 11 Pro 25H2 (Build 26200), AMD Ryzen 9 5900X (12 Kerne/24 Threads), 64 GB RAM, NVIDIA RTX 3090 | Leistung reicht für Proxys mit Software-Kodierung. |
| **Virtualisierung** | `VirtualizationFirmwareEnabled: False`, `HypervisorPresent: False` | **Laut Abfrage ist die Virtualisierung im BIOS (AMD SVM) aus.** Docker Desktop läuft so nicht. Vor Docker: SVM im BIOS einschalten, Neustart. |
| WSL | nicht installiert | Docker Desktop braucht WSL2: Installation mit Administratorrechten und Neustart. |
| Docker | nicht installiert | – |
| Python | 3.14.4 installiert (Aufruf über `py`); `python.exe` im Pfad ist nur der Platzhalter des Microsoft Store | Für Weg B wäre Python schon da. |
| ffmpeg | `C:\Program Files\ffmpeg\ffmpeg.exe`, Version unbekannt | Wird nicht genutzt (Grundsatz: ffmpeg nur im Container). Nur zur Kenntnis. |
| Laufwerke | `C:` 887 GB frei, `D:` („Stuff“) 1.084 GB frei | Genug Platz für Aufnahmen einer Produktion. |
| ELSA-Freigaben | `T:` Bilderarchiv, `V:` Projekte, `W:` Schnittplatz_Arbeitsver, `X:` Proxy_Output, `Y:` Aufnahmen, `Z:` Software_und_Tools | `Software_und_Tools` ist verbunden, also geeignet für den zentralen Ablageort von Skript und `.bat`. |
| Netzwerk | 2,5 GbE (Realtek) | Kopieren nach ELSA theoretisch knapp 300 MB/s. |
| Programme | DaVinci Resolve 20.0 und 21.0, Resolve Control Panels, Premiere Pro 2025, **TeraCopy 4.0.5**, Syncthing | Ob Resolve Studio oder Free, verrät der Programmname nicht. TeraCopy ist da: für die Messung der Altersgrenze (D3) mit TeraCopy und Explorer messen. |

**Antworten der Kollegen (12.11.2026):**
1. In Frage kommen möglichst **alle** Schnittrechner. → Die Einrichtung muss je Rechner wiederholbar und einfach sein; Anleitung `phase0/Schnittrechner_Einrichtung_Docker.md`.
2. Kopiert wird mit **Explorer oder TeraCopy**. → Die Messung D3 mit beiden Programmen.
3. Proxys werden aus dem Ordner `Proxies/` neben den Aufnahmen per **„Link Proxy“ in Resolve** eingebunden („halb-automatisch“). → Name und Ort des lokalen Proxys (`<Ordner>/Proxies/<Name>.mov`) dürfen sich nicht ändern; das ist im Plan so vorgesehen. Nach dieser Antwort greifen die Schnittplätze nicht auf die zentrale Kopie in `Proxy_Output` zu; gebraucht wird sie für den Katalog des Bandarchivs.

**Fehler in der ersten Fassung der Anleitung:** `wsl --list --verbose` bietet bei fehlendem WSL die Installation an („beliebige Taste drücken“). Hier ist nach 60 s ohne Eingabe nichts passiert. Die Abfrage ist korrigiert (nur Paketliste und Registry).

**Folge für die Sprachfrage:** Docker am Schnittrechner ist mehr als eine Installation: BIOS-Einstellung, WSL2 und Docker Desktop, jeweils mit Administratorrechten und Neustarts. Das gilt für Weg A und Weg B gleichermaßen, weil ffmpeg in beiden Wegen im Container läuft. D4 (Testlauf) kann erst danach stattfinden.

## Stand der Sprachfrage

Beide Wege sind auf ELSA möglich. Für Weg A (Bash, am Schnittrechner im Container) fehlt nur noch der Testlauf mit Docker Desktop unter Windows (Geschwindigkeit des Laufwerkszugriffs).
