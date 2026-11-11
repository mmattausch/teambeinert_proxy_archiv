# Phase 0: Auswertung ELSA

Stand: 11.11.2026 · Messung auf ELSA am 11.11.2026, 22:41–22:45 (Block A und B aus `README.md`). Rohdaten in `phase0/ergebnisse/` (nicht im Repository, enthalten Projektnamen).

Einträge aus `Aufnahmen/00_PRIVAT` wurden aus den lokalen Listen entfernt und nicht ausgewertet.

## Noch offen

- **`archiv_h264.sh` fehlt.** Die Kopie in `/tmp/phase0` gehört root und ist für `scp` nicht lesbar (Quelle hat `rwxrwx---`, `cp` als root übernimmt das ohne Leserecht für andere). Auf ELSA als root: `chmod 644 /tmp/phase0/archiv_h264.IST-STAND.sh.txt`, dann nur diese Datei holen.
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

Nach Code gefolgert, am echten Proxy noch nicht gesehen. Prüfen mit einem vorhandenen Proxy einer `DSCF*.MP4`:

```bash
docker run --rm --pull never -v /mnt/Aufnahme_mirror/Aufnahmen:/mnt/Aufnahme_mirror/Aufnahmen:ro --entrypoint ffprobe linuxserver/ffmpeg -v error -show_entries stream=index,codec_type,width,height -of compact "<Pfad zu Proxies/DSCFxxxx.mov>"
```

Für v5.0 bleibt es wie in v4 (Gleichheit). Folge für die Prüfung M3: Die Zahl der Videospuren im Proxy ist nicht immer 1. Geprüft wird deshalb „gleich wie die Zuordnung von v4 sie ergibt“, nicht „gleich wie im Original“.

## Stand der Sprachfrage

Beide Wege sind auf ELSA möglich. Für Weg A (Bash, am Schnittrechner im Container) fehlt nur noch der Testlauf mit Docker Desktop unter Windows (Geschwindigkeit des Laufwerkszugriffs).
