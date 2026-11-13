# Umsetzungsplan Proxy-Skript v5 und Archivskript

Stand: 11.11.2026 (fünfte Fassung) · Strang PX · Maßnahmen M-01 und M-39 · Status: **Entwurf, wartet auf Freigabe durch Michl**

Grundlage:
- `../teambeinert_IT_wissen/docs/themen/proxy-archiv-kontext.md`, `proxy-und-archivskript.md`, `docs/entscheidungen.md`, `docs/arbeitsregeln.md`
- Proxy-Skript v4 im Ist-Stand: `../teambeinert_IT_wissen/docs/referenz/proxy_conv_docker_v4.IST-STAND.sh.txt`
- Archivskript im Ist-Stand: `../teambeinert_IT_wissen/docs/referenz/archiv_h264.IST-STAND.sh.txt` (vom 09.01.2026, geholt 11.11.2026). Vergleich mit v4 in `phase0/auswertung.md`: Timecode und Ton-Logik sind identisch.
- „Archivskript: nötige Änderungen“ vom 11.11.2026 (von Michl, M3 angepasst am 12.11.2026): `docs/Archivskript_Aenderungen.md`, im Folgenden **Änderungsliste**, Kennungen M1 bis M16.
- Anforderungen von Michl vom 11.11.2026: Betrieb des Proxy-Skripts auch am Windows-Schnittrechner; ffmpeg überall im Container; `R:` ohne eigenen Programmaufwand; **Proxy- und Archivskript aus einer Codebasis**.

Alles unter „Empfehlung“ ist ein Vorschlag von Claude und noch nicht beschlossen.

---

## 1. Ziel und Grundsatz

Eine Codebasis, aus der zwei Programme entstehen:

1. **Proxy-Skript v5** ersetzt `proxy_conv_docker_v4.sh`: Schnitt-Proxys (540p) für `Aufnahmen`, täglich auf ELSA und bei Bedarf am Windows-Schnittrechner.
2. **Archivskript** ersetzt das heutige `archiv_h264.sh`: Archiv-Fassungen (H.264, volle Auflösung) für Aufträge des Werkzeugs „Bandarchiv“. Danach werden Originale gelöscht, die Archiv-Fassung ist dann die einzige Fassung.

Beide tun im Kern dasselbe: Videodateien finden, mit ffprobe untersuchen, mit ffmpeg im Container umrechnen, Ergebnis prüfen, ablegen, protokollieren. Sie unterscheiden sich in den ffmpeg-Parametern, im Ziel, in der Eingabe und in der Strenge der Prüfung. Das wird je **Profil** festgelegt, alles andere ist gemeinsam.

**Grundsatz (Änderungsliste): Die Funktion bleibt gleich.** Je Profil bleiben die ffmpeg-Parameter, die Zielnamen und die Ordnerstruktur genau wie heute:

| | Proxy | Archiv |
|---|---|---|
| Ziel | zentral `Proxy_Output/mnt/Aufnahmen/<Pfad>/<Name>.<ext>.mov` und lokal `<Ordner>/Proxies/<Name>.mov` | `Aufnahmen/00_to_Backup/h264_archiv/<Pfad>/<Name>.<ext>.mov` |
| ffmpeg (heute) | 540p, yuv420p, libx264 main/2.1, CRF 21, veryfast, fastdecode, keyint 75, AAC, 4 Threads | volle Auflösung, yuv420p10le, libx264, CRF 18, veryfast, fastdecode, keyint 75, AAC, 4 Threads |
| Endungen | `mp4`, `mxf`, `mov`, `mpeg`, `avi`, `mts`, Groß/klein egal (für beide und das Werkzeug dieselbe Liste) | |

**Wichtig für die Gleichheit:** Gemeinsamer Code nur dort, wo beide Skripte heute nachweislich gleich arbeiten (Timecode, Ton-Logik, Endungen). Weicht `archiv_h264.sh` irgendwo von v4 ab, bleibt die Abweichung im Archiv-Profil erhalten. Das wird nach dem Lesen von `archiv_h264.sh` Zeile für Zeile festgestellt (Abschnitt 6).

**ffmpeg läuft überall im Container `linuxserver/ffmpeg`** mit demselben festen Digest: kein eigener Build, überall dasselbe ffmpeg und x264.

Was an der Kodierung auffällt (Abschnitt 8), wird nur geprüft und dokumentiert. Eine Korrektur wäre ein neues Profil (M10) mit eigener Freigabe.

---

## 2. Betriebsarten

| | **Proxy auf ELSA** | **Proxy am Schnittrechner** | **Archiv auf ELSA** |
|---|---|---|---|
| Aufruf | TrueNAS-Cronjob 20:00; von Hand per `systemd-run` | `proxy <Pfad>` in der Konsole, `.bat` zum Draufziehen | `archiv_h264.sh --auftrag <Datei>` per `systemd-run --unit=archiv-<Auftrag>` (Befehl erzeugt das Werkzeug); weiter auch `archiv_h264.sh <Datei>` |
| Eingabe | ganz `Aufnahmen` durchsuchen | angegebener Ordner samt Unterordnern | Auftragsdatei: je Zeile ein absoluter Pfad einer Datei (M5) |
| Ausschlüsse | `Aufnahmen/00_*`, `Aufnahmen/01_*` (erster Ordner), `Proxies/`, versteckte Dateien | `Proxies/`, versteckte Dateien | wie Proxy auf ELSA, übersprungene Dateien mit Grund ins Protokoll (M7) |
| Altersgrenze | 120 Minuten | aus | aus (das Werkzeug wählt die Dateien) |
| Vorhandenes Ziel | wie v4: beide da → nichts; eines fehlt → kopieren; keines → umrechnen | `Proxies/<Name>.mov` da → nichts | geprüft nach M3 → `vorhanden_ok`, sonst `Fehler` (Fortsetzen eines Auftrags, M5) |
| Prüfung nach dem Umrechnen (M3) | Laufzeit, erste Videospur Höhe 540, Summe Tonkanäle, Größe | wie links | Laufzeit, erste Videospur **gleiche Auflösung wie im Original**, Summe Tonkanäle, Größe |
| Protokoll (M4) | `Proxy_Output/_protokolle/<Datum>.csv` | Zusammenfassung in der Konsole (Datei: offen) | `h264_archiv/_protokolle/<Auftrag>.csv` |
| Parallelität | 3 wie heute | 3, einstellbar | 3 wie heute (`xargs -P 3`), einstellbar |
| `--nur-pruefen` (M6) | vorhandene Proxys gegen Original | – | Bestand in `h264_archiv` gegen Original, Pflicht vor dem ersten Löschen |

**Aufrufe heute** (Angabe Michl, 11.11.2026):

- Proxy, TrueNAS-Cronjob als root (entspricht der Zeile in der IT-Doku):
  `/usr/bin/find /mnt/Aufnahme_mirror/Aufnahmen/ -type f ! -name ".*" \( -iname "*.mp4" -o … -iname "*.mts" \) -print0 | /usr/bin/xargs -0 -n 1 -P 3 …/proxy_conv_docker_v4.sh > …/log_proxy_Elsa.log 2>&1`
- Archiv, von Hand je Ordner, im Vordergrund mit `sudo`:
  `sudo /usr/bin/find /mnt/Aufnahme_mirror/Aufnahmen/<Projekt>/<Unterordner>/ -type f ! -name ".*" \( … \) -print0 | /usr/bin/xargs -0 -n 1 -P 3 /mnt/Mirror_2x8TB/Proxy_Output/archiv_h264.sh`

Folgerungen für den Entwurf:
- **Der Einzeldatei-Aufruf muss parallel laufen können.** `archiv_h264.sh <Datei>` bleibt erhalten (Änderungsliste M5) und wird heute dreifach parallel gestartet. Die Sperre gegen doppelte Läufe (M13) gilt deshalb im Einzeldatei-Aufruf **je Zieldatei**, nicht für das ganze Programm. Die Sperre für den ganzen Lauf gilt nur bei `--auftrag` und beim Proxy-Lauf. Einzelaufrufe schreiben ins Protokoll `_protokolle/einzel_<Datum>.csv`; jede Zeile wird unter einer Sperre auf die CSV angehängt, damit sich parallele Aufrufe nicht ins Wort fallen.
- **Rückgabewerte bleiben mit `xargs` brauchbar:** Endet ein Einzelaufruf mit 1 oder 2, meldet `xargs` am Ende 123. Damit sieht man nach dem heutigen Aufruf erstmals, ob etwas schiefging.
- **Der heutige Archiv-Aufruf läuft im Vordergrund unter `sudo`.** Endet die SSH-Sitzung, bricht er ab (Stolperstein `log_subcmds`, siehe Arbeitsregeln); mit dem heutigen Skript bleibt dann eine halbe Archiv-Fassung als „existiert“ liegen. Mit M1 und M12 ist das künftig harmlos. Für lange Ordner trotzdem `systemd-run` nutzen; die Anleitung bekommt dafür einen fertigen Befehl, der den heutigen `find | xargs`-Aufruf in eine Unit packt.
- Für den Proxy ersetzt v5 die Cron-Zeile durch einen einzigen Aufruf, der selbst sucht (Abschnitt 3). **Der Einzeldatei-Aufruf `proxy_v5.sh <Datei>` bleibt zusätzlich erhalten** (Michl, 11.11.2026), z. B. für einen Ordner von Hand per `find | xargs` wie beim Archiv; gleiche Regeln: Sperre je Zieldatei, Protokoll `einzel_<Datum>.csv`, Rückgabewerte 0/1/2. Ausschlüsse, Bestandsabgleich (beide Kopien) und Prüfung wie im Lauf; nur die Altersgrenze entfällt, weil die Datei bewusst übergeben wird.

**Ablauf bei einer zeitkritischen Produktion:** Aufnahmen auf den Schnittrechner kopieren, `proxy <Ordner>` starten, Schnitt vorbereiten. Danach den Ordner wie üblich nach `Aufnahmen` kopieren. Abends findet ELSA den lokalen Proxy, kopiert ihn über eine Teildatei in die zentrale Ablage, rechnet nicht neu. Das ist der Fall „nur `Proxies/` vorhanden“ aus v4, ohne zusätzliche Prüfung.

**Reihenfolge beim Archiv (Änderungsliste M7):** umgerechnet wird, solange der Ordner unter `Aufnahmen/<Projekt>` liegt; erst danach verschiebt das `mv`-Skript des Werkzeugs nach `00_to_Backup/<Band>/`.

---

## 3. Aufbau der Codebasis

```
gemeinsam              Kern für alle Betriebsarten
  auswahl              Endungen, Ausschlüsse, Altersgrenze, Auftragsdatei lesen
  probe                ffprobe: Spuren, Kanäle je Spur, Laufzeit, Auflösung; Timecode wie heute
  ton                  Ton-Zuordnung (bis 8 Kanäle / Aufteilung in Mono), aus v4 übertragen
  container            ffmpeg/ffprobe im Container: Image-Digest, Einbindungen, --user, --name, -nostdin
  ablage               Teildatei .teil mit -f mov, Prüfung (M3), mv -n, Kopie über Teildatei, Platz (M14), Rechte (M9)
  protokoll            CSV nach M4, Fehlerliste, Zusammenfassung, Zeitstempel, Rückgabewerte 0/1/2
  ablauf               Sperre (M13), Abbruch (M12), Aufräumen alter .teil, Parallelität, --trocken, --nur-pruefen
profile
  proxy_h264_540_v1    ffmpeg-Argumente aus v4, Ziele zentral + Proxies/, Prüfung Höhe 540
  archiv_h264_crf18_v1 ffmpeg-Argumente aus archiv_h264.sh, Ziel h264_archiv, Prüfung gleiche Auflösung
einstiege
  proxy_v5.sh          Proxy auf ELSA und (über proxy.bat) am Schnittrechner
  archiv_h264.sh       Archiv; Name und Aufrufe bleiben, weil das Werkzeug „Bandarchiv“ sie so erwartet
  proxy.bat            Windows
tests/                 Testdateien-Erzeuger, Gleichheitsvergleiche, Fälle aus Abschnitt 10
docs/                  Einrichtung ELSA, Anleitung Schnitt, Befunde zur Kodierung
```

Ein Profil ist eine kleine, eigenständige Beschreibung: Kennung, ffmpeg-Argumente, Zielpfade, Prüfregeln. Ein neues Profil (z. B. `…_v2` nach einer bewussten Änderung) kommt dazu, ohne den Kern anzufassen; die alte Kennung bleibt für nachvollziehbare Protokolle bestehen.

**Sprache: Bash (Beschluss Michl, 13.11.2026).** Auf ELSA läuft das Skript auf dem Host und startet ffmpeg/ffprobe je Aufruf im Container, wie heute. Am Schnittrechner startet `proxy.bat` das ganze Skript im Container (`docker run … --entrypoint bash linuxserver/ffmpeg@<Digest> …`); Bash, `find` und `flock` kommen aus dem Image. Das Skript erkennt an einer Umgebungsvariable, die nur `proxy.bat` setzt, ob es ffmpeg direkt aufruft (im Container) oder per `docker run` (ELSA); das ist eine Stelle im Kern, kein zweiter Code. Gemeinsamer Code als `lib/*.sh`, die alle Einstiege einbinden.

**Tests auf dem Mac:** Der Mac ist arm64; Docker holt dort für denselben Digest die arm64-Fassung von ffmpeg. Für Funktionstests reicht das. Gleichheitstests (`framemd5`) laufen auf ELSA oder auf dem Mac mit `--platform linux/amd64` (emuliert, nur kurze Testdateien). Docker läuft auf dem Mac über Colima; Colima bindet nur Ordner unter dem Benutzerverzeichnis ein, deshalb liegen Testdaten in `tests/daten/` (nicht im Repository, `.gitignore`). Testdateien erzeugt `tests/erzeuge_testdateien.sh` (45 Dateien: bösartige Namen, Tonaufbauten 1–16 Kanäle und gemischt, Timecode mit und ohne Drop-Frame, MXF, MTS, zwei Videospuren, ungerade Breite, Hochformat, 10 Bit 4:2:2, defekt, ohne Video, Ausschlussordner).

---

## 4. Punkte der Änderungsliste je Programm

| Nr. | Proxy | Archiv | Gemeinsam im Kern |
|---|---|---|---|
| M1 Teildatei `.teil`, `-f mov`, `mv -n` | ja, auch für Kopien lokal ↔ zentral | ja | ja |
| M2 Rückgabewerte 0/1/2 | ja | ja | ja |
| M3 Prüfung | Höhe 540 | gleiche Auflösung; auch für vorhandene Ziele (`vorhanden_ok`) | Prüfregeln je Profil |
| M4 Protokoll-CSV | Empfehlung: ja, gleiches Format | ja | ja |
| M5 Auftragsdatei, Standardeingabe schützen | Standardeingabe ja | ja | ja |
| M6 `--nur-pruefen` | Empfehlung: ja | ja | ja |
| M7 `00_`/`01_` nur am ersten Ordner | schon so in v4 | **Änderung**: heute trifft `00_` an beliebiger Stelle | ja |
| M8 Image mit Digest | ja | ja, dasselbe Image | ja |
| M9 Rechte `2775`, `--user <uid>:1003`, gezielte Einbindungen | ja | ja | ja |
| M10 Profilkennung | `proxy_h264_540_v1` | `archiv_h264_crf18_v1` | ja |
| M11 kein `eval` | ja | ja | ja |
| M12 Abbruch mit `trap`, `docker stop` | ja | ja | ja |
| M13 `flock` | Lauf: `Proxy_Output/_protokolle/.sperre`; Einzeldatei: je Zieldatei | `--auftrag`: `h264_archiv/_protokolle/.sperre`; Einzeldatei: je Zieldatei | ja |
| M14 Platz | `Mirror_2x8TB` und `Aufnahme_mirror` | `Aufnahme_mirror` (84 %) | ja |
| M15 `systemd-run`, Zeitstempel, Zusammenfassung | ja (Cron weiter über TrueNAS) | ja | ja |
| M16 Änderungszeit übernehmen | nein (v4 lässt das Umrechnungsdatum) | **offen** (Empfehlung der Änderungsliste) | Schalter je Profil |

Proxy und Archiv laufen mit getrennten Sperren und können gleichzeitig laufen. Ob das die Last auf ELSA verträgt, zeigt der Betrieb; sonst eine gemeinsame Sperre.

---

## 5. Freigabe für das Löschen (Archiv)

Nicht Teil des Skripts, aber das, worauf es ankommt (Änderungsliste, Abschnitt 6): Das Werkzeug gibt den Löschbefehl für einen Ordner nur frei, wenn die letzte Protokollzeile jeder Datei aus der Auftragsdatei `ok`, `vorhanden_ok` oder `kein_video` lautet und die Archiv-Fassung mit der protokollierten Größe vorhanden ist. Deshalb gilt für das Archiv:

- Kein Weg führt an der Prüfung vorbei: Eine Datei unter endgültigem Namen ist immer geprüft (M1, M3).
- Alte Archiv-Fassungen aus der Zeit vor der Überarbeitung gelten erst nach `--nur-pruefen` als geprüft (M6).
- Das Skript löscht nie Originale und nie fertige Archiv-Fassungen; es löscht nur eigene `.teil`-Reste.

---

## 6. Gleichheit nachweisen (M11)

Für jedes Profil gegen sein heutiges Skript:

1. ffmpeg-Argumente Zeile für Zeile übertragen, mit allen Eigenheiten.
2. Erst `archiv_h264.sh` gegen v4 vergleichen: Was ist wirklich gleich (Timecode, Ton-Logik, Endungen, Ausschlüsse)? Nur das wandert in den Kern.
3. Je Testdatei: alte `echo`-Zeile gegen die neue Argumentliste. Abweichen dürfen nur `-nostdin`, `-f mov`, `.teil`, `--user`, `--name`, fehlendes `-i` bei `docker run` und die Einbindungen.
4. Bild und Ton: `ffmpeg -i <datei> -map 0 -f framemd5 -` für alte und neue Ausgabe, gleiches Image. Erwartet: gleich. Grundlage ist der Testkorpus `Aufnahmen/2025-03-04_PROXY` (Abschnitt 10).
5. Proxy am Schnittrechner gegen Proxy auf ELSA, gleiches Image, `framemd5`. Erwartet: gleich.

---

## 7. Phase 0: Daten aufnehmen (nur lesend, vor dem Code)

**Stand 11.11.2026:** ELSA-Teil erledigt, auch die Ist-Fassung von `archiv_h264.sh`; Auswertung in `phase0/auswertung.md`. Schnittrechner VFX-WORKSTATION erhoben (12.11.2026): Virtualisierung im BIOS aus, kein WSL, kein Docker; vor jedem Docker-Test sind BIOS-Einstellung, WSL2 und Docker Desktop nötig. Offen: weitere Rechner, Fragen 0.11 und 0.13, Testlauf 0.12. Festgeschrieben für M8: `linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697` (ffmpeg 8.0). Bash, GNU find und flock sind im Image vorhanden, Python 3.11.9 auf dem Host.

**ELSA**

| # | Abfrage | Wozu |
|---|---|---|
| 0.1 | `cat /mnt/Mirror_2x8TB/Proxy_Output/archiv_h264.sh`, als `archiv_h264.IST-STAND.sh.txt` nach `docs/referenz/` im Wissens-Repo (Aufruf heute: erledigt, Abschnitt 2) | Ist-Stand Archiv, Vergleich mit v4 |
| 0.2 | `sha256sum` von v4 gegen die Kopie im Wissens-Repo; Cronjob-Zeile ablesen; `ls -l /mnt/Mirror_2x8TB/Proxy_Output/*.sh` | Ist-Stand Proxy, weitere Varianten |
| 0.3 | `docker image inspect linuxserver/ffmpeg --format '{{index .RepoDigests 0}}'`, `docker run --rm linuxserver/ffmpeg -version \| head -3` (ohne vorher zu pullen) | Digest für M8 |
| 0.4 | `docker run --rm --entrypoint bash linuxserver/ffmpeg -c 'bash --version; find --version; flock --version'` | Weg A |
| 0.5 | `stat` und `getfacl` von `Aufnahmen`, einem `Proxies/`-Ordner, `Proxy_Output/mnt/Aufnahmen`, `00_to_Backup/h264_archiv` | UID für `--user`, ob `2775` auf den ACL-Datasets greift |
| 0.6 | Umfang von `h264_archiv`: Anzahl Dateien, Größe; Platz der `Proxies/`-Ordner | `--nur-pruefen`-Lauf planen; Schwachstelle (f) |
| 0.7 | Dateien im Wurzelordner `Aufnahmen`; Paare mit gleichem Namen und verschiedenen Videoendungen (auch in `bandinhalt_dateien.tsv.gz`) | Befunde 5 und 6 |
| 0.8 | ffprobe-Stichprobe über 50–100 Dateien: Spuren, Kanäle je Spur, Timecode | Testmenge |
| 0.9 | Letztes `log_proxy_Elsa.log` | Ausgangslage |

**Schnittrechner**

| # | Frage | Wozu |
|---|---|---|
| 0.10 | Welche Rechner, Windows-Version, CPU, RAM; Docker Desktop vorhanden? | Einrichtung |
| 0.11 | Eine große Datei wie üblich nach `Aufnahmen` kopieren und währenddessen auf ELSA mehrmals `stat`: Ist die Änderungszeit während des Kopierens „jetzt“? | Altersgrenze |
| 0.12 | Testdatei im Container über Docker Desktop umrechnen, Zeit messen | Weg A, Laufwerkszugriff |
| 0.13 | Wie binden die Schnittplätze die Proxys ein (Resolve Free/Studio)? | Testfälle |

---

## 8. Befunde zur Kodierung: nur prüfen, nicht ändern

Aus v4 (am Code belegt); für `archiv_h264.sh` nach 0.1 zu ergänzen. Die Änderungsliste (Abschnitt 5) nennt für das Archiv weitgehend dieselben Punkte.

1. **Tonspuren mit 3, 5 oder 7 Kanälen** fallen in v4 in den `else`-Zweig und werden wie „mehr als 8“ in Monospuren geteilt.
2. **Mehr als 8 Kanäle:** `-map 0:0 -map 0:1` nimmt Spur 0 und 1 unabhängig von ihrer Art; der Filter greift immer auf `[0:a]`; bei gemischten Spuren hängt das Ergebnis von der Reihenfolge ab. Die Prüfung der Kanalsumme (M3) kann solche Dateien erstmals als `Fehler` melden. Beim Proxy gewollt sichtbar; beim Archiv verhindert sie zu Recht das Löschen.
3. **Ohne Tonspur** bleibt `video_map` leer; ffmpeg wählt selbst.
4. Proxy: **`-level 2.1`** passt rechnerisch nicht zu 540p; **`scale=-1:540`** kann ungerade Breiten liefern. Beide: kein Deinterlacing, Log-Material nicht getaggt. Archiv: `fastdecode`, 10 Bit 4:2:0 und AAC sind bewusst getragene Kompromisse (Änderungsliste 5.1–5.3).
5. **Gleicher Name mit verschiedenen Videoendungen im selben Ordner** (`A001.mp4`, `A001.mxf`): Nach dem Code von v4 bilden beide denselben lokalen Proxy-Namen `Proxies/A001.mov`, zentral verschiedene; die zweite Datei bekommt den Proxy der ersten. **Gemessen 11.11.2026: kommt in `Aufnahmen` nicht vor** (`phase0/auswertung.md`). Das Archiv ist nicht betroffen, es behält die Endung im Namen.
6. **Dateien direkt im Wurzelordner `Aufnahmen`:** In v4 entsteht ein falscher zentraler Pfad. **Gemessen: keine Videodateien im Wurzelordner.**
7. **Timecode** aus der Textausgabe von `ffmpeg -i`, erster Treffer. In der Stichprobe (100 Dateien) stimmt er überall mit dem Timecode der Datei überein.
8. **Zweite Videospur** (neu aus Phase 0): Bei Dateien mit Ton nimmt `-map 0:v` alle Videospuren. Überwachungskameras (`DSCF*.MP4`, 1920×1080 + 320×176) bekommen so eine zweite, hochgerechnete Videospur (982×540) im Proxy; Drohnen ohne Ton (Video + MJPEG-Vorschaubild) nicht, dort wählt ffmpeg selbst. **Am echten Proxy bestätigt (11.11.2026, lokal und zentral gleich).** Außerdem trägt der Proxy je Videospur eine Timecode-Datenspur (`-timecode` mit mov). **Kein Sonderfall (Michl, 12.11.2026):** Die Proxys der Überwachungskameras werden nicht genutzt und spielen in QuickTime; das genügt. Der Code behandelt zwei Videospuren nicht gesondert. Die Prüfung M3 bezieht sich deshalb nur auf die **erste Videospur** (Proxy: Höhe 540; Archiv: Auflösung wie die erste Videospur des Originals); die Anzahl der Video- und Datenspuren wird nicht geprüft.

9. **`00_` an beliebiger Stelle (nur Archiv, Änderungsliste M7):** Das heutige `archiv_h264.sh` überspringt jeden Pfad mit `00_`. Gemessen: 77 Videodateien (171 GB) außerhalb von `00_*`-Ordnern, fast alle Telefonvideos `VID_JJJJMMTT_hhmmss_…`. Sie würden heute still nicht umgerechnet. Wird mit M7 behoben (bewusste Änderung, keine Kodierung betroffen).

Befunde 1, 2, 3, 7 und 8 gelten für das Archivskript genauso, die Ton- und Timecode-Logik ist dort identisch.

Mehr als 8 Kanäle oder 3/5/7 Kanäle kamen in der Stichprobe nicht vor (Befunde 1 und 2); typisch sind 1 Stereospur oder 4 Monospuren (Sony FX3).

---

## 9. Umsetzungsreihenfolge

**Empfehlung:** Kern von Anfang an für beide Profile bauen, aber nacheinander in Betrieb nehmen.

1. **Phase 0** (Abschnitt 7). Erledigt bis auf die Schnittrechner; Sprache Bash festgelegt (13.11.2026).
2. **Kern + Profil Proxy**, Tests, Ausrollen auf ELSA. Zuerst, weil die Lücke in v4 (Befehlsausführung als root, M-01) der dringendste Punkt ist.
3. **Profil Archiv**, Tests nach Änderungsliste Abschnitt 7, Ausrollen. `--nur-pruefen` über den Bestand in `h264_archiv`.
4. **Proxy am Schnittrechner**, Einrichtung und Anleitung für die Kollegen.

Schritt 3 kann früher kommen, wenn das Werkzeug „Bandarchiv“ früher löschen will; die Reihenfolge stimmt Michl mit dem Strang BK ab. Zwischen 2 und 3 ändert sich der Kern nur, wenn das Archiv etwas braucht, das der Proxy nicht hat; dann wird der Proxy erneut gegen v4 geprüft.

---

## 10. Tests

### Testkorpus `Aufnahmen/2025-03-04_PROXY` (Vorgabe Michl, 12.11.2026)

Echte Aufnahmen aller Kamerasysteme, die im Einsatz sind; Grundlage der bisherigen Tests des Proxy-Skripts. **Jede Änderung wird gegen diesen Ordner getestet.** Laut Dateiliste vom 11.11.2026: 63 Originale, 22,2 GB, davon

| Ordner | Inhalt |
|---|---|
| `FX3`, `a7iv` | Sony XAVC HS/S/S-I, H.264/H.265, 4:2:0/4:2:2, 8/10 Bit, 4-Kanal-Ton |
| `FS7` | MPEG HD 422, XAVC-I/-L (MXF), ProRes 422/HQ |
| `GH5` | AVCHD 50i und 50p (MTS), MOV/MP4 8/10 Bit, All-I, HEVC, LPCM |
| `Sumo` | ProRes 422/HQ/LT, **1080i 59,94**, 1080p, UHD 50p/59,94p |
| `Hyperdeck` | ProRes 422 LT mit **16 Tonkanälen**, H.265 4K |
| `URSA` | DNxHD 220x, ProRes 422/444/XQ |
| `shogun` | DNxHR HQ, ProRes 422 |
| `Mavic3`, `Avatar`, `GoPro` | DJI ProRes LT, H.264/H.265 in MOV/MP4, 5K, 2,7K 120p, 5312×2988 Zeitraffer |
| `Ordner mit Leerzeichen` | Leerzeichen, Umlaute und Sonderzeichen im Pfad |

Damit sind Interlaced, mehr als 8 Kanäle (Befund 2), 10 Bit, 4:2:2, ProRes 444/XQ und Sonderzeichen mit echten Dateien abgedeckt. Nicht abgedeckt sind die bösartigen Namen aus Test 2 (`$(…)`, Backticks usw.); dafür bleiben erzeugte Testdateien.

**Ergebnis der Untersuchung (12.11.2026, `phase0/auswertung.md`):** Die vorhandenen Proxys stammen aus zwei Läufen vor v4 (zentral März 2025, lokal 09.11.2025) und sind keine v4-Referenz. Die beiden lokalen Proxys in `Ordner mit Leerzeichen` sind **abgebrochen** (1,70 s bzw. 0,83 s statt 6,62 s), die zentralen vollständig. Der Korpus enthält damit einen echten Fall für Schwachstelle (b) und für `--nur-pruefen`.

**Gleichheitstest gegen den Korpus** (Abschnitt 6, Empfehlung):
1. **Referenz erzeugen:** v4 und `archiv_h264.sh` unverändert laufen lassen, nur die Pfadvariablen (`searchpath`, `basedir`) auf ein Testverzeichnis umgestellt, damit nichts im echten `Aufnahmen` oder `Proxy_Output` entsteht. Beim Proxy liegt die lokale Kopie neben dem Original; dafür wird der Korpus einmal in das Testverzeichnis kopiert (22 GB).
2. **v5 und neues Archiv** über denselben Korpus, Ziel ebenfalls im Testverzeichnis, Quelle nur lesend.
3. **Vergleich je Datei, automatisch:** übergebene ffmpeg-Argumente; `framemd5` von Bild und Ton; `ffprobe -show_streams`. Ergebnis als Tabelle (Datei, gleich/ungleich, Grund). Das Testverzeichnis legt Michl fest (Platz, möglichst ohne Replikation).
4. Derselbe Vergleich später für den Proxy vom Schnittrechner gegen den von ELSA.

Daraus wird ein Test-Skript im Repository (`tests/korpus_vergleich.sh`), das bei jeder Änderung erneut läuft.

### Weitere Tests

Erzeugte Testdateien auf dem Mac mit Docker und demselben Digest (für Fälle, die der Korpus nicht hat), nichts Echtes im Repository. Windows-Teil mit Docker Desktop.

Für beide Profile:
1. **Gleichheit** nach Abschnitt 6.
2. **Namen** mit Leerzeichen, Umlauten, `'`, `"`, `$`, `` ` ``, `;`, `&`, `[`, `]`, `:` (nur Linux), führendem `-`, sehr lang. Nachweis: `clip$(touch /tmp/pwned).mp4` erzeugt `/tmp/pwned` nicht.
3. **Ton:** keine Spur, 1/2/4/6/8 Kanäle, 3/5/7 Kanäle, mehr als 8, mehrere Spuren, gemischt.
4. **Videoendung ohne Video** → `kein_video`.
5. **Timecode:** ohne, Drop-Frame, in Spur und Metadaten.
6. **Abbruch** mitten in der Umrechnung (`systemctl stop`, Strg+C, Fenster schließen): kein Ziel unter endgültigem Namen, keine Teildatei, kein weiterlaufender Container, Zeile `abgebrochen`; erneuter Start setzt fort.
7. **Defekte Quelle** (`head -c 10M`): `Fehler`, Rückgabewert 1, übrige Dateien `ok`.
8. **Zwei gleichzeitige Läufe** desselben Programms: der zweite endet mit 2.
9. **Ausschluss:** `Aufnahmen/00_to_Backup/…` und `Aufnahmen/01_x/…` übersprungen, `…/Tag_100_Bühne.mxf` umgerechnet, nichts aus `Proxies/`.
10. **Platz zu knapp:** `Fehler`/`zu wenig Platz`.
11. **`--nur-pruefen`** gegen fertige und gegen eine absichtlich abgeschnittene Ausgabe.
12. **Rechte** (auf ELSA): neue Ordner `rwxrwsr-x`, Gruppe `Firma`, Dateien gehören nicht root.

Nur Proxy:
13. **Altersgrenze:** Datei jünger als 120 Minuten wird nicht angefasst.
14. **Schnittrechner-Ablauf:** Ordner unter Windows verarbeiten, nach ELSA kopieren, ELSA-Lauf ergänzt nur die zentralen Proxys.

Nur Archiv:
15. **Auftragsdatei mit mehreren Dateien:** alle Zeilen werden abgearbeitet (Standardeingabe, M5); Leerzeilen und `#`-Zeilen ignoriert.
16. **Fortsetzen:** zweiter Lauf desselben Auftrags → fertige Dateien `vorhanden_ok`, Rest umgerechnet; CSV angehängt, letzte Zeile je Quelle gilt.
17. **Heutiger Aufruf** (gilt ebenso für `proxy_v5.sh <Datei>`): `find … -print0 | xargs -0 -n 1 -P 3 archiv_h264.sh` über einen Testordner: alle Dateien `ok`, keine Datei doppelt umgerechnet, CSV vollständig und ohne verschränkte Zeilen; dieselbe Datei zweimal gleichzeitig gestartet → einer rechnet, der andere meldet „belegt“.
18. **CSV-Format:** UTF-8 ohne BOM, LF, Semikolon, Quoting nach RFC 4180 bei Namen mit `;`, `"`, Leerzeichen.

---

## 11. Ausrollen (führt Michl aus)

**Proxy auf ELSA**
1. v5 nach `Proxy_Output/` kopieren, v4 bleibt liegen.
2. `--trocken` per `systemd-run --unit=proxy-v5-probe` gegen den echten Baum; Ergebnis gemeinsam ansehen.
3. `--nur-pruefen` über den Bestand; Fehlerliste durchgehen.
4. Echter Lauf gegen einen Testordner, klein halten.
5. Cronjob in der TrueNAS-Oberfläche auf v5 umstellen, 20:00 bleibt.
6. Drei Abendläufe prüfen, Stichproben in Resolve.

**Archiv auf ELSA**
1. Neue Fassung neben die alte legen (alte umbenennen, nicht löschen); Aufrufname `archiv_h264.sh` bleibt.
2. `--nur-pruefen` über den Bestand in `h264_archiv`; was durchfällt, löscht Michl von Hand und rechnet neu.
3. Testauftrag mit einem kleinen Ordner, Protokoll mit dem Werkzeug „Bandarchiv“ gegenlesen.

**Schnittrechner**
1. Docker Desktop einrichten, Image mit demselben Digest holen.
2. Skript und `.bat` zentral auf `Software_und_Tools`, Verknüpfung auf dem Desktop.
3. Eine Produktion begleitet durchspielen, danach Anleitung an die Kollegen.

Jeweils Eintrag im Änderungsprotokoll (`docs/it-dokumentation.md`, Abschnitt 15) und Status in `docs/massnahmen.md` (M-01, M-39).

**Rückweg:** Cronjob zurück auf v4 bzw. alte `archiv_h264.sh` zurückbenennen. Die neue Fassung hinterlässt nur fertige, geprüfte Ausgaben an denselben Orten, dazu `_protokolle/`.

## 12. Fertig, wenn

- Schwachstellen (a) bis (e) in beiden Programmen nachweislich behoben.
- Gleichheit mit v4 und mit dem heutigen `archiv_h264.sh` belegt; Schnittrechner und ELSA liefern dieselben Proxys.
- Drei Abendläufe Proxy auf ELSA ohne unerklärte Fehler; ein Archiv-Auftrag vom Werkzeug bis zum Protokoll durchgespielt; Bestand in `h264_archiv` geprüft.
- Schnittrechner-Ablauf einmal mit echtem Material durchgespielt.
- Einrichtung, Rückweg und Anleitung dokumentiert, Wissens-Repository nachgetragen.

---

## 13. Geklärt am 11.11.2026 (Beschlüsse und Anforderungen Michl)

In `../teambeinert_IT_wissen/docs/entscheidungen.md` bzw. `themen/proxy-und-archivskript.md` eingetragen.

- Sammelordner für Bandpakete: `Aufnahmen/00_to_Backup/<Band>/`.
- Archiv-Fassungen unter `Aufnahmen/00_to_Backup/h264_archiv/`, Pool `Aufnahme_mirror`.
- Codec Archiv: H.264 mit den unveränderten Einstellungen von `archiv_h264.sh`, auch für `R:`.
- Alle Videodateien eines Ordners werden umgerechnet.
- `R:` am Z420 ist ein einmaliger Sonderfall ohne eigenen Programmaufwand.
- Proxy-Skript auch am Windows-Schnittrechner.
- ffmpeg überall im Docker-Container, kein eigener Build; Prozesspriorität unverändert.
- Proxy- und Archivskript aus einer Codebasis.
- Beide Programme behalten den Einzeldatei-Aufruf (parallel per `xargs` nutzbar).

**Noch offen:**
- ~~Sprache~~: Bash (13.11.2026).
- M16 (Änderungszeit) beim Archiv.
- Manifest vom Archivskript oder Prüfsummen nur vom Werkzeug.
- Protokolldatei am Schnittrechner: ob und wo.
- Reihenfolge Proxy/Archiv im Betrieb (Abschnitt 9), mit Strang BK abzustimmen.
- Platz in `Aufnahme_mirror` (84 %): Archiv-Fassungen liegen dort zusätzlich zu den Originalen, bis das Band geprüft ist.

---

## 14. Stand der Umsetzung (13.11.2026)

**Code:** `lib/kern.sh` (gemeinsamer Kern), `lib/proxy_profil.sh` (ffmpeg-Argumente, Timecode, Ton-Zuordnung aus v4), `proxy_v5.sh` (Abendlauf, `--datei`, `--lokal`, `--nur-pruefen`, `--trocken`, `--befehl`). Noch nicht: Archiv-Profil, `proxy.bat`, Einrichtung und Anleitung.

**Tests** (in der Colima-VM auf dem Mac, Linux mit Bash 5.2, GNU-Werkzeugen, flock, Docker):
- `tests/lauf_tests.sh`: 49 von 49 Prüfungen bestanden – Abendlauf, zweiter Lauf ändert nichts, fehlende Kopie wird ergänzt, zwei gleichzeitige Läufe, Abbruch per `TERM` (kein Proxy, keine Teildatei, kein Container übrig, Protokoll „abgebrochen“), Einzelaufrufe auch parallel, Prüflauf findet abgeschnittenen Proxy, Schnittrechner-Modus mit anschließendem Abendlauf, kein Dateiname wird als Befehl ausgeführt.
- `tests/v4_vergleich.sh`: v4 (nur Pfade angepasst, `docker` als Attrappe) gegen v5, je Testdatei die übergebenen ffmpeg-Argumente. 32 gleich, 7 erwartete Unterschiede, 0 ungleich. Die erwarteten Unterschiede sind Fehler von v4: Bei 4 Dateien zerlegt `eval` den Namen (Anführungszeichen, Zeilenumbruch, `$(…)`, Backticks; die beiden letzten führt v4 tatsächlich als Befehl aus), bei 2 nicht lesbaren Dateien startet v4 ffmpeg trotzdem, bei 1 Datei (Tonspuren 2 + 16 Kanäle) fehlt in v4 ein Leerzeichen (`0:a-map`), ffmpeg scheitert in beiden.

- `tests/korpus_vergleich.sh`: v4 (echt, nur die Pfadvariablen `basedir`, `proxydest`, `proxydestfile` aufs Testverzeichnis) und v5 rechnen dieselben Dateien, Vergleich von Bild und Ton per `framemd5`. Probelauf in der Colima-VM mit den 39 Testdateien und identischem Image: **27 bitgleich**, 12 erklärt (eval-Namen, nicht lesbare Quellen, ffmpeg scheitert in beiden), **0 ungleich**. Der Lauf am echten Testkorpus auf ELSA steht aus (Anleitung `tests/LIESMICH.md`); der Testordner wird dabei nicht verändert.

**Neue Befunde aus den Tests:**
- **Befund 11: v4 hinterlässt leere Proxys.** Scheitert ffmpeg, bleibt in der zentralen Ablage eine Datei mit 0 Byte, die v4 nach `Proxies/` kopiert. Beide gelten danach als fertig; die Datei wird nie neu gerechnet. Betroffen sind alle Fälle, in denen ffmpeg scheitert (z. B. 16 Kanäle, ungerade Breite). Ob es solche Dateien auf ELSA gibt, zeigt eine lesende Abfrage (`tests/LIESMICH.md`). v5 legt in diesen Fällen nichts ab und meldet `Fehler`.
- **Befund 10: Mehr als 8 Kanäle in einer Spur scheitern in v4 (und damit in v5).** Die Zuordnung `-map 0:0 -map 0:1` nimmt die Spur mit 16 Kanälen zusätzlich zu den Monospuren auf; AAC kann höchstens 8 Kanäle, ffmpeg bricht ab. Betrifft HyperDeck-Aufnahmen mit 16 Kanälen. Der vorhandene Proxy im Testkorpus stammt aus einer älteren Skriptfassung. Am Testkorpus auf ELSA mit dem echten v4 zu bestätigen. Behebung nur als neues Profil.
- **Befund 4 präzisiert:** Bei ungerader Ausgangsbreite (z. B. 1918×1080) ergibt `scale=-1:540` eine ungerade Breite (959); x264 verweigert das, es entsteht **kein** Proxy (in v4 wie in v5).
- 3, 5 und 7 Kanäle (Befund 1): Der Proxy hat doppelt so viele Kanäle wie das Original (z. B. 3 → 6), ist aber brauchbar.

**Abweichungen von v4 und von der Änderungsliste, ausdrücklich benannt:**
1. **Ton-Prüfung beim Proxy (bestätigt von Michl, 13.11.2026):** Statt gleicher Kanalsumme (M3) nur „Proxy hat Ton genau dann, wenn das Original Ton hat“. Grund: Mit gleicher Kanalsumme lieferte v5 bei 3/5/7 Kanälen gar keinen Proxy mehr, wo v4 einen brauchbaren liefert. Beim Archiv bleibt der Vergleich der Kanalsumme.
2. **`-hide_banner -loglevel error`** zusätzlich im ffmpeg-Aufruf: nur kürzere Ausgabe, kein Einfluss auf die Datei.
3. **Dateien direkt im Wurzelordner `Aufnahmen`** (Befund 6): v5 bildet den zentralen Pfad richtig (`<ZENTRAL>/<Name>.<ext>.mov`), v4 falsch. Kommt laut Messung nicht vor.
4. **Nicht lesbare Quellen und Dateien ohne Videospur:** v5 startet ffmpeg gar nicht erst, sondern meldet `Fehler` bzw. `kein_video`. v4 startet ffmpeg und scheitert ohne Meldung.
5. **Umgebung auf dem Mac:** Die Tests laufen in der Colima-VM, nicht direkt auf macOS (dort nur Bash 3.2). Das Skript setzt Bash ≥ 4.4 voraus (ELSA und Container haben 5.2).

**Offen für den nächsten Schritt:** Testkorpus auf ELSA (v4-Referenz und `framemd5`-Vergleich, braucht das Testverzeichnis von Michl), Archiv-Profil, `proxy.bat` und Test am Schnittrechner, `docs/einrichtung-elsa.md`, `docs/anleitung-schnitt.md`.
