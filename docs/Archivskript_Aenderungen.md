# Archivskript: nötige Änderungen

Stand: 2026-11-11 · Bezug: `archiv_h264.sh` auf ELSA (`/mnt/Mirror_2x8TB/Proxy_Output/archiv_h264.sh`), gelesen am 2026-11-11 · Für: die Weiterentwicklung des Archiv- und Proxy-Skripts (eigener Strang)

## 1. Worum es geht

Das Archivskript rechnet Videodateien aus `Aufnahmen` in eine H.264-Archiv-Fassung um. Bisher sind die Originale danach noch da, und ein Fehler fällt spätestens beim nächsten Blick auf. Künftig nimmt das Bandarchiv-Werkzeug die Archiv-Fassungen aufs Band, und nach bestandener Bandprüfung werden **die Originale gelöscht**. Ab dann ist die Archiv-Fassung die einzige Fassung des Materials.

Deshalb muss das Skript jede Datei nachweisbar vollständig umrechnen oder einen Fehler melden. Das Werkzeug gibt den Löschbefehl nur frei, wenn das Protokoll des Skripts für jede Videodatei eines Ordners `ok` meldet.

**Grundsatz für alle Änderungen:** Die Funktion bleibt gleich. Das betrifft vor allem die ffmpeg-Befehle mit allen Parametern, die Zielnamen und die Ordnerstruktur. Die Änderungen betreffen nur das, was um den ffmpeg-Aufruf herum passiert: Eingabe, Fehlerbehandlung, Prüfung, Protokoll, Rechte, Abbruch. Abschnitt 5 nennt Beobachtungen zur Kodierung, ausdrücklich nur zum Prüfen und nicht zum Ändern.

Fast alle Punkte in Abschnitt 3 gelten genauso für das Proxy-Skript (siehe Abschnitt 8).

## 2. Was das Skript heute tut

- Aufruf mit einer Datei als `$1`, vermutlich aus einem `find … -exec` oder einer Schleife.
- Ziel: `/mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup/h264_archiv/<Pfad relativ zu Aufnahmen>/<Name>.<ext>.mov`. Das ist ein Spiegel von `Aufnahmen`, mit der Originalendung im Namen, wie bei den Proxys.
- Übersprungen werden Pfade mit `00_` an beliebiger Stelle, Pfade unter `Aufnahmen/01_…` und Pfade mit `/Proxies/`.
- Existiert die Zieldatei, endet das Skript mit „existiert“.
- Timecode: aus der Ausgabe von `ffmpeg -i`, erster Treffer, sonst `00:00:00:00`.
- Ton: ffprobe zählt die Kanäle je Tonspur. Bis 8 Kanäle wird `-map 0:a` genommen, bei mehr als 8 wird in Monospuren aufgeteilt.
- ffmpeg im Container `linuxserver/ffmpeg` ohne feste Version: libx264, CRF 18, `veryfast`, `fastdecode`, `yuv420p10le`, volle Auflösung, AAC, `keyint=75`, 4 Threads.
- Der Befehl wird als Zeichenkette gebaut und mit `eval` ausgeführt.
- Kein Protokoll. Rückgabewert ist immer 0.

## 3. Muss-Änderungen

Jeder Punkt hat eine Kennung (M1, M2 …), damit man sich in Tickets und Commits darauf beziehen kann.

### M1 Erst in eine Teildatei schreiben, dann umbenennen

**Heute:** ffmpeg schreibt direkt unter den endgültigen Namen. Bricht der Lauf ab (Neustart von ELSA, Platte voll, `systemctl stop`, Absturz von ffmpeg), bleibt eine halbe Datei liegen. Beim nächsten Lauf gilt sie als „existiert“ und wird nie mehr erneuert. Nach dem Löschen des Originals ist das Material dann verloren.

**Neu:**
- ffmpeg schreibt nach `<Name>.<ext>.mov.teil` im selben Zielordner.
- **Wichtig:** ffmpeg erkennt das Ausgabeformat an der Endung, `.teil` kennt es nicht. Deshalb `-f mov` vor den Ausgabenamen setzen. Am Inhalt der Datei ändert das nichts, der mov-Muxer ist derselbe, der bei `.mov` automatisch gewählt wird.
- Erst wenn ffmpeg mit 0 endet **und** die Prüfung nach M3 bestanden ist: `mv -n` auf den endgültigen Namen. `mv` im selben Ordner ist eine Umbenennung und atomar.
- Damit gilt: Eine Datei unter dem endgültigen Namen ist immer vollständig und geprüft.
- Beim Start alte `*.mov.teil` im Zielbaum des Auftrags löschen. Das sind Reste abgebrochener Läufe, die Umrechnung beginnt für diese Dateien neu.

### M2 Fehler erkennen und weitergeben

**Heute:** Der Rückgabewert von ffmpeg wird nicht ausgewertet, das Skript endet immer mit 0.

**Neu:**
- `set -u` und `set -o pipefail`. `set -e` nur, wenn man jede erwartete Fehlerstelle bewusst abfängt; sonst lieber jede Stelle einzeln prüfen.
- Rückgabewert von ffmpeg und ffprobe je Datei auswerten. Fehler gehen ins Protokoll (M4), die Teildatei wird gelöscht, und das Skript macht mit der nächsten Datei weiter. Ein Fehler in einer Datei hält den Auftrag nicht an.
- Rückgabewert des Skripts:
  - `0`: alle Dateien `ok` oder zulässig übersprungen
  - `1`: mindestens eine Datei mit `Fehler`
  - `2`: Aufruf- oder Umgebungsfehler (Auftragsdatei fehlt, Sperre belegt, Zielordner nicht beschreibbar, Docker nicht erreichbar). In diesem Fall wurde nichts umgerechnet.

### M3 Die fertige Datei prüfen, bevor sie als fertig gilt

Mit ffprobe Original und Teildatei vergleichen:

| Prüfung | Bedingung für `ok` |
|---|---|
| Laufzeit (`format=duration`) | Abweichung höchstens 1,0 Sekunden (einstellbar, Variable `TOLERANZ_SEKUNDEN`) |
| Videospur | genau so viele Videospuren wie im Original nach der jeweiligen Zuordnung (heute meist 1) |
| Auflösung | Breite und Höhe wie im Original, weil die Archiv-Fassung nicht skaliert |
| Tonspuren | Anzahl der Tonkanäle in der Summe wie im Original. Bei mehr als 8 Kanälen sind es Monospuren, die Summe der Kanäle muss trotzdem passen |
| Größe | größer als 0 |

Werte von Original und Archiv-Fassung kommen ins Protokoll (M4), damit das Werkzeug sie anzeigen und selbst nachprüfen kann.

Hat eine Datei mit Videoendung keine Videospur, z. B. eine `.mov` nur mit Ton, wird sie nicht umgerechnet. Ergebnis `kein_video`, siehe M4. Das Werkzeug nimmt diese Datei dann 1:1 mit aufs Band.

### M4 Protokoll je Auftrag als CSV

Pfad: `/mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup/h264_archiv/_protokolle/<Auftrag>.csv`. Der Ordnername beginnt mit `_`, damit er nicht mit einem Projektordner verwechselt wird. Das Werkzeug liest ihn über seinen nur lesenden Zugriff auf `Aufnahmen`.

Format:
- UTF-8 ohne BOM, Zeilenende LF, Trennzeichen Semikolon, erste Zeile Kopfzeile.
- Jedes Feld, das `;`, `"` oder ein Leerzeichen enthält, in `"…"`, innere `"` verdoppelt (RFC 4180). In Bash am einfachsten mit einer kleinen Funktion, die jedes Feld so ausgibt.
- Zeitpunkte als `YYYY-MM-DD HH:MM:SS` in Ortszeit, Laufzeiten in Sekunden mit Punkt als Dezimaltrenner (wie ffprobe), Größen in Byte.
- Jede Zeile wird geschrieben, sobald die Datei fertig ist, nicht erst am Ende. Bricht der Lauf ab, steht alles Fertige schon drin.
- Läuft ein Auftrag ein zweites Mal, werden Zeilen angehängt. Es gilt die letzte Zeile je Quelle.

Spalten:

| Spalte | Inhalt |
|---|---|
| `auftrag` | Kennung des Auftrags, z. B. `A0007` |
| `quelle` | absoluter Pfad des Originals |
| `ziel` | absoluter Pfad der Archiv-Fassung (endgültiger Name), leer bei `kein_video` |
| `ergebnis` | `ok`, `vorhanden_ok`, `kein_video`, `uebersprungen`, `Fehler` |
| `meldung` | Grund bei `Fehler` oder `uebersprungen`, z. B. `ffmpeg Rückgabewert 1`, `Laufzeit weicht 12,4 s ab`, `Pfad enthält 00_` |
| `groesse_quelle`, `groesse_ziel` | Byte |
| `laufzeit_quelle`, `laufzeit_ziel` | Sekunden |
| `aufloesung_quelle`, `aufloesung_ziel` | `1920x1080` |
| `videospuren_quelle`, `videospuren_ziel` | Anzahl |
| `tonkanaele_quelle`, `tonkanaele_ziel` | Summe der Kanäle über alle Tonspuren |
| `timecode` | übernommener Timecode |
| `beginn`, `ende` | Zeitpunkte |
| `profil` | Kennung der Kodier-Einstellungen, siehe M10 |
| `ffmpeg_image` | Image mit Digest, siehe M8 |
| `skript_version` | Version des Skripts |

`vorhanden_ok` heißt: Die Archiv-Fassung lag schon da und hat die Prüfung nach M3 bestanden. Für Dateien, die nach M1 entstanden sind, ist das immer der Fall. Für ältere Dateien aus dem heutigen Skript siehe M6.

### M5 Auftragsdatei als Eingang

Neben dem bisherigen Aufruf mit einer Datei (bleibt für Proxy-Skript-ähnliche Abläufe erhalten) kommt ein Aufruf mit einer Auftragsdatei dazu:

```
archiv_h264.sh --auftrag /mnt/Container_space/apps/bandarchiv/daten/archivauftraege/A0007.txt
```

- Das Werkzeug schreibt die Auftragsdatei in sein eigenes Datenverzeichnis. Dort darf es schreiben, und das Skript liest sie über den Pfad auf ELSA. Das Werkzeug schreibt damit nirgends sonst auf ELSA.
- Format: UTF-8, LF, je Zeile ein absoluter Pfad einer **Datei** unter `/mnt/Aufnahme_mirror/Aufnahmen/`. Keine Ordner, keine Muster: Das Werkzeug legt die Liste fest und kann dann beweisen, dass zu jeder Originaldatei entweder sie selbst oder ihre Archiv-Fassung aufs Band kommt. Leerzeilen und Zeilen mit `#` am Anfang ignorieren.
- Die Kennung des Auftrags ist der Dateiname ohne `.txt`.
- Pfade mit Zeilenumbruch kann es in dieser Datei nicht geben. Das Werkzeug lässt solche Dateien nicht in einen Auftrag und meldet sie.
- **Wichtig, wenn das Skript die Auftragsdatei in einer `while read`-Schleife liest:** `docker run -i` und ffmpeg lesen die Standardeingabe. Innerhalb der Schleife verschlucken sie dann die restlichen Zeilen der Auftragsdatei, und der Auftrag endet still nach der ersten Datei. Abhilfe, beides:
  - die Auftragsdatei über einen eigenen Kanal lesen: `while IFS= read -r -u 3 zeile; do …; done 3< "$auftrag"`
  - bei allen `docker run` innerhalb der Schleife `-i` weglassen oder `< /dev/null` anhängen, bei ffmpeg zusätzlich `-nostdin`. `-nostdin` ändert nichts an der Ausgabe.
- Fortsetzbar: Ein zweiter Lauf mit derselben Auftragsdatei überspringt fertige Dateien (endgültiger Name vorhanden und geprüft, Ergebnis `vorhanden_ok`) und rechnet nur den Rest.

### M6 Nur prüfen, ohne umzurechnen

```
archiv_h264.sh --nur-pruefen --auftrag …/A0007.txt
```

Rechnet nichts um. Prüft für jede Quelle, ob die Archiv-Fassung existiert und M3 besteht, und schreibt das Protokoll. Fehlt die Archiv-Fassung oder besteht sie die Prüfung nicht: `Fehler` mit Grund. Gelöscht wird dabei nichts.

Das braucht es für den **Bestand in `h264_archiv`**. Diese Dateien hat das heutige Skript ohne Teildatei geschrieben, eine abgebrochene Datei ist von einer fertigen nicht zu unterscheiden. Bevor dazu Originale gelöscht werden, muss jede dieser Dateien einmal so geprüft sein. Was durchfällt, wird von Hand gelöscht und neu umgerechnet.

### M7 Ausschlussregeln am richtigen Pfadteil prüfen

**Heute:** `case "$1" in *"00_"*)` trifft jeden Pfad, der irgendwo `00_` enthält, auch im Dateinamen, z. B. `Tag_100_Bühne.mxf` oder `MVI_2100_….mov`. Solche Dateien werden still übersprungen.

**Neu:** Wie bei `01_` (dort ist es schon richtig gelöst) nur den ersten Ordner unter `Aufnahmen` prüfen:

```bash
if [[ "$1" =~ ^/mnt/Aufnahme_mirror/Aufnahmen/0[01]_[^/]*/ ]]; then
```

Übersprungene Dateien mit Grund ins Protokoll (`uebersprungen`, M4). Das Werkzeug zeigt sie dann an, statt dass sie einfach fehlen.

Die Regel für `/Proxies/` bleibt. Das Werkzeug nimmt Dateien aus `Proxies/` gar nicht erst in die Auftragsdatei, sie gehen 1:1 aufs Band.

**Reihenfolge:** Umgerechnet wird, solange der Ordner noch in `Aufnahmen/<Projekt>` liegt. Erst danach verschiebt das `mv`-Skript des Werkzeugs nach `00_to_Backup/<Band>/`. Dort würde das Skript die Dateien wegen `00_` überspringen.

### M8 Feste Version des ffmpeg-Images

**Heute:** `linuxserver/ffmpeg` ohne Tag, also `latest`. Ein `docker pull` oder ein Update von TrueNAS kann ffmpeg und x264 wechseln. Damit ändern sich unbemerkt die Ausgabe und unter Umständen die Verträglichkeit mit DaVinci, und die Dateien sind nicht mehr „von der gleichen Art“.

**Neu:**
- Zuerst die heute benutzte Version festhalten, ohne etwas zu ändern:
  ```
  docker image inspect linuxserver/ffmpeg --format '{{index .RepoDigests 0}}'
  docker run --rm linuxserver/ffmpeg -version | head -3
  ```
- Im Skript genau dieses Image mit Digest eintragen, z. B. `linuxserver/ffmpeg@sha256:…`, als eine Variable `FFMPEG_IMAGE` für alle drei Aufrufe (Timecode, ffprobe, ffmpeg).
- Proxy- und Archivskript nutzen dasselbe Image, solange beide gleich kodieren sollen.
- Ein Wechsel des Images ist eine bewusste Änderung mit Test (Abschnitt 7) und einem neuen Profil (M10).
- Den Digest ins Protokoll schreiben (M4).

### M9 Rechte

**Heute:** `mkdir -m 777`. ffmpeg läuft im Container als root, die Archiv-Fassungen gehören deshalb vermutlich root.

**Neu:**
- Ordner mit `mkdir -m 2775` anlegen. Das setgid-Bit hält die Gruppe `Firma` (GID 1003) wie im übrigen `Aufnahmen`.
- Container mit Benutzer und Gruppe starten: `docker run --user <uid>:1003 …`. Welche UID, entscheidet der Strang. Am einfachsten ist ein eigener Dienstbenutzer in der Gruppe `Firma`.
- Optional, für mehr Sicherheit: Statt `-v /mnt:/mnt` nur einbinden, was gebraucht wird. `Aufnahmen` nur lesend, `h264_archiv` darüber schreibbar:
  ```
  -v /mnt/Aufnahme_mirror/Aufnahmen:/mnt/Aufnahme_mirror/Aufnahmen:ro
  -v /mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup/h264_archiv:/mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup/h264_archiv
  ```
  Die Pfade im Container bleiben gleich, die Befehle ändern sich also nicht. Ein Fehler im Skript kann dann keine Originale überschreiben.

### M10 Kodier-Einstellungen als Profil mit Kennung

Die ffmpeg-Parameter bleiben, wie sie sind. Sie bekommen aber einen Namen und eine Version, z. B. `ARCHIV_PROFIL="h264_crf18_v1"`, und die Kennung steht in jeder Protokollzeile. Wird später ein Parameter geändert, entsteht `…_v2`. So lässt sich auch nach Jahren sagen, welche Archiv-Fassung mit welchen Einstellungen entstanden ist und welche Dateien „von der gleichen Art“ sind.

Die Kennung **nicht** als Metadaten in die Videodatei schreiben, das würde die Ausgabe verändern. Sie steht nur im Protokoll. Das Werkzeug legt sie zusätzlich in die Datei `_ARCHIV-FASSUNG.csv` auf dem Band.

### M11 Kein `eval`, Befehl als Bash-Array

**Heute:** Der ffmpeg-Befehl wird als Zeichenkette gebaut und mit `eval` ausgeführt. Ein `"`, `$`, `` ` `` oder `\` im Datei- oder Ordnernamen bricht den Befehl oder führt Teile des Namens als Befehl aus.

**Neu:** Den Befehl als Array aufbauen:

```bash
cmd=(docker run --rm --name "$container_name" --user "$uid:1003" -v … "$FFMPEG_IMAGE"
     -nostdin -i "$inputfile" -pix_fmt yuv420p10le -timecode "$time_code")
cmd+=("${filter_args[@]}" "${video_map_args[@]}" "${audio_map_args[@]}")
cmd+=(-c:v libx264 -c:a aac -preset veryfast -tune fastdecode -crf 18 -threads 4
      -x264opts keyint=75 -f mov "$ziel/$filename.teil")
"${cmd[@]}"
```

`filter_args`, `video_map_args` und `audio_map_args` werden ebenfalls als Arrays gebaut. Bei `filter_complex` entfallen dann die zusätzlichen Anführungszeichen, die heute nur für `eval` nötig sind: Das Array-Element ist der Filtertext selbst, z. B. `-filter_complex "[0:a]pan=mono|c0=c0[a0];[0:a]pan=mono|c0=c1[a1]"` wird zu den zwei Elementen `-filter_complex` und `[0:a]pan=mono|c0=c0[a0];[0:a]pan=mono|c0=c1[a1]`. Ebenso `-map` und `[a0]` als zwei Elemente.

**Weil hier sehr leicht unabsichtlich etwas anders wird:** Für jede Testdatei die tatsächlich an ffmpeg übergebenen Argumente von alter und neuer Fassung vergleichen, z. B. mit `printf '%q\n' "${cmd[@]}"` gegen die mit `echo` ausgegebene alte Zeile. Abweichen dürfen nur `-nostdin`, `-f mov`, `.teil`, `--user`, `--name` und die Einbindungen (siehe Abschnitt 7).

### M12 Sauber abbrechen

- `docker run` mit `--name archiv_<auftrag>_<pid>`.
- `trap` auf `TERM`, `INT` und `HUP`: `docker stop` für diesen Container, Teildatei löschen, Protokollzeile `Fehler` mit `abgebrochen`, Ende mit Rückgabewert 1.
- Grund: Wird nur der `docker run`-Prozess beendet, etwa durch `systemctl stop` oder das Ende einer Sitzung, läuft der Container unter Umständen weiter und schreibt die Datei fertig, während das Skript schon weg ist.

### M13 Nur ein Lauf gleichzeitig

Mit `flock` auf `h264_archiv/_protokolle/.sperre`. Ist sie belegt: Meldung und Rückgabewert 2. Zwei Läufe auf dieselben Dateien würden sich sonst gegenseitig Teildateien löschen.

### M14 Platz vorher prüfen

Vor jeder Datei den freien Platz im Ziel-Dataset prüfen (`df --output=avail -B1`). Unter einer Reserve, Vorschlag: Größe der Quelldatei plus 50 GB, die Datei nicht beginnen. Ergebnis `Fehler` mit `zu wenig Platz`, und der Auftrag endet mit Rückgabewert 1. Eine Archiv-Fassung kann größer werden als das Original, wenn das Original schon stark komprimiert ist, z. B. HEVC vom Telefon.

### M15 Start und Ausgabe

- Start nur mit `systemd-run --unit=archiv-<auftrag> …`, wie auf ELSA vereinbart. Den genauen Befehl erzeugt das Werkzeug.
- Ausgaben mit Zeitstempel `YYYY-MM-DD HH:MM:SS` am Zeilenanfang. Sie landen im Journal der Unit (`journalctl -u archiv-A0007`).
- Am Ende eine Zusammenfassung: Anzahl `ok`, `vorhanden_ok`, `kein_video`, `uebersprungen`, `Fehler`.

### M16 Änderungszeit übernehmen (Empfehlung)

Nach dem Umbenennen `touch -r "$inputfile" "$ziel/$filename"`. Die Archiv-Fassung trägt dann das Datum der Aufnahme statt des Umrechnungstags. Das hilft in der Ordnerübersicht, in Suche und Katalog des Bands und in DaVinci beim Sortieren. Am Bild und Ton ändert das nichts. Wenn ihr die Proxys heute bewusst mit dem Umrechnungsdatum lasst, beim Archivskript genauso halten und M16 weglassen.

## 4. Welche Dateien umgerechnet werden

Entscheidung 2026-11-11: **alle Videodateien eines Ordners, unabhängig von der Größe**, damit alle Archiv-Fassungen von der gleichen Art sind. Alles andere (Ton, Fotos, Projektdateien, Sidecar-Dateien wie `.xml` oder `.XMP`, `Proxies/`) kommt 1:1 aus dem Originalordner mit aufs Band.

Die Auswahl trifft das Werkzeug beim Erzeugen der Auftragsdatei:
- Endung `mp4`, `mxf`, `mov`, `mpeg`, `avi` oder `mts`, unabhängig von Groß- und Kleinschreibung, also z. B. auch `.MP4` und `.MOV`. Das ist dieselbe Liste wie beim Proxy-Skript (`-iname`).
- ohne versteckte Dateien (Name beginnt mit `.`, z. B. die `._`-Dateien vom Mac)
- ohne Dateien unter `Proxies/`

Bitte im Strang abgleichen, ob diese Liste genau der des Proxy-Skripts entspricht. Gibt es dort weitere Endungen oder Ausnahmen, gilt dieselbe Liste für beide Skripte und das Werkzeug.

Dateien mit Videoendung ohne Videospur meldet das Skript als `kein_video` (M3). Das Werkzeug nimmt sie dann 1:1 mit.

## 5. Kodierung: nur prüfen, nicht ändern

Die ffmpeg-Befehle sind mit viel Aufwand auf die Tücken der einzelnen Kameras und Rekorder und auf DaVinci abgestimmt. Die Verträglichkeit mit den bestehenden Proxys und Archiv-Fassungen hat Vorrang. Die folgenden Punkte sind deshalb **keine Änderungswünsche**, sondern Stellen, die man mit Testdateien einmal gezielt ansehen sollte. Wenn sich etwas davon als Fehler herausstellt, wird es als neues Profil (M10) behoben, nicht still.

1. **`-tune fastdecode`** schaltet in x264 unter anderem CABAC und das Deblocking ab. Für Proxys im Schnitt ist das gewollt, weil sie schneller dekodieren. Für eine Archiv-Fassung kostet es bei gleicher Qualität spürbar mehr Platz. Nur zur Kenntnis.
2. **`yuv420p10le`** ergibt H.264 High 10. Viele Abspielprogramme und die Hardware-Dekoder mancher Macs können das nicht. Quellen mit 4:2:2 (viele Rekorder und MXF) verlieren die halbe Farbauflösung. Beides ist ein bekannter, bewusst getragener Kompromiss. Nur zur Kenntnis.
3. **Ton als AAC:** verlustbehaftet. `-c:a copy` wäre verlustfrei, ändert aber die Art der Dateien und ist deshalb nicht vorgeschlagen.
4. **Mehr als 8 Kanäle**, bitte mit einer solchen Datei prüfen:
   - `video_map="-map 0:0 -map 0:1"` nimmt die Spuren mit Index 0 und 1, unabhängig von ihrer Art. Ist Spur 1 die vielkanalige Tonspur, landet sie zusätzlich zu den Monospuren in der Ausgabe. AAC kann höchstens 8 Kanäle, ffmpeg bricht dann womöglich ab. Mit M2 würde man das jetzt erstmals bemerken.
   - Bei **mehreren** Tonspuren mit mehr als 8 Kanälen greift `[0:a]` im Filter immer auf die erste Tonspur zu. Die zweite würde dann nicht umgerechnet, stattdessen käme die erste doppelt.
   - Bei gemischten Tonspuren (eine bis 2 Kanäle, eine mit mehr als 8) wird `audio_map` in der Schleife einmal überschrieben und einmal ergänzt. Das Ergebnis hängt von der Reihenfolge der Spuren ab.
   - Gibt es solche Dateien gar nicht, reicht ein Satz in der Doku.
5. **Ohne Tonspur** ist `video_map` leer. ffmpeg wählt dann selbst und nimmt bei mehreren Videospuren nur eine. Das betrifft nur Dateien mit mehreren Videospuren.
6. **Timecode:** wird aus der Textausgabe von `ffmpeg -i` gelesen, erster Treffer. Bei Dateien mit mehreren Timecodes (Spur und Metadaten) kann das ein anderer sein, als DaVinci anzeigt. Bisher offenbar unauffällig.

Nicht in diese Liste gehört, was oben unter M1 bis M16 steht. Das ändert die Ausgabe nicht.

## 6. Was das Werkzeug mit dem Ergebnis macht

Zum Verständnis für den Strang, damit klar ist, worauf es ankommt:

1. Michl markiert einen Ordner mit Inhalt `Archiv-Fassung`. Das Werkzeug erzeugt die Auftragsdatei (alle Videodateien des Ordners, Abschnitt 4) und den Startbefehl. Michl startet ihn.
2. Das Werkzeug liest `_protokolle/<Auftrag>.csv` und prüft selbst nach: Für jede Zeile der Auftragsdatei muss die letzte Protokollzeile `ok`, `vorhanden_ok` oder `kein_video` sein, und die Archiv-Fassung muss mit der protokollierten Größe da sein. Sonst steht der Ordner auf `Fehler beim Umrechnen`, mit der Meldung aus dem Protokoll.
3. Das Paket für das Band besteht aus den Archiv-Fassungen (an der Stelle des Originals, mit dem Namen `<Name>.<ext>.mov`) und allen übrigen Dateien des Ordners 1:1, dazu `_ARCHIV-FASSUNG.csv` im Projektordner. Diese Datei listet je umgerechneter Datei Originalname, Originalgröße, Laufzeit und Profil. So erklärt sich das Band auch ohne das Werkzeug.
4. Prüfsummen (xxHash3-64) rechnet das Werkzeug selbst für das ganze Paket. Ein Manifest vom Archivskript ist deshalb nicht nötig. Das weicht vom Schnittstellenvorschlag in `CLAUDE.md` ab und ersetzt ihn.
5. Nach bestandener Bandprüfung erzeugt das Werkzeug den Löschbefehl für den Originalordner und die Archiv-Fassungen im Sammelordner. Michl bestätigt vorher ausdrücklich, dass die Originale verworfen werden.

## 7. Testplan für die neue Fassung

1. **Testordner:** je Kamera und Rekorder, der vorkommt, eine kurze Datei, dazu die Problemfälle: mehr als 8 Kanäle, mehrere Tonspuren, keine Tonspur, Videoendung ohne Video, Timecode in Spur und Metadaten. Den Ordner als Kopie unter einem Projektnamen in `Aufnahmen` anlegen, nicht unter `00_…`.
2. **Gleiche Ausgabe:** jede Testdatei einmal mit der alten und einmal mit der neuen Fassung umrechnen, mit demselben Image. Dann vergleichen:
   - die an ffmpeg übergebenen Argumente (M11). Erlaubt sind nur die dort genannten Abweichungen.
   - die dekodierten Bilder und den Ton: `ffmpeg -i <datei> -map 0 -f framemd5 -` für alt und neu, die Ausgaben müssen gleich sein. x264 ist mit gleichen Einstellungen und gleicher Thread-Zahl in der Regel reproduzierbar. Sind die Prüfsummen trotzdem verschieden, wenigstens `ffprobe -show_streams` vergleichen und die Datei in DaVinci gegenprüfen.
3. **Namen:** Dateien und Ordner mit Leerzeichen, Umlauten, `'`, `"`, `$`, `` ` ``, `;`, `&`, `[`, `]` im Namen. Alle müssen umgerechnet werden und richtig im Protokoll stehen.
4. **Auftragsdatei mit mehreren Dateien:** prüfen, dass wirklich alle Zeilen abgearbeitet werden (M5, Standardeingabe).
5. **Abbruch:** während einer Umrechnung `systemctl stop archiv-…`. Erwartet: Container gestoppt, keine Teildatei, Protokollzeile `abgebrochen`. Danach denselben Auftrag erneut starten: Fertiges wird übersprungen, der Rest umgerechnet.
6. **Fehler:** eine kaputte Videodatei (z. B. mit `head -c 10M` abgeschnitten) in den Auftrag. Erwartet: `Fehler`, Rückgabewert 1, die übrigen Dateien trotzdem `ok`.
7. **Ausschluss:** eine Datei mit `00_` im Namen wird umgerechnet, eine Datei in `Aufnahmen/00_irgendwas/` wird als `uebersprungen` protokolliert.
8. **Nur prüfen (M6):** gegen einen Teil des Bestands in `h264_archiv` laufen lassen, und gegen eine absichtlich abgeschnittene Kopie einer Archiv-Fassung. Die muss als `Fehler` erkannt werden.
9. **Rechte:** Neue Ordner haben `rwxrwsr-x` und die Gruppe `Firma`, neue Dateien gehören nicht root.

## 8. Proxy-Skript

Dieselben Punkte gelten fürs Proxy-Skript: M1 (Teildatei), M2 (Fehler), M7 (`00_`), M8 (feste Version), M9 (Rechte), M11 (kein `eval`), M12 (Abbruch). Für das Bandarchiv-Werkzeug ist das Proxy-Skript weniger heikel, weil dort nichts gelöscht wird. Ein halber Proxy fällt aber im Katalog als Video auf, das mittendrin endet, und wird vom Skript nie erneuert.

Für den Katalog wichtig und bitte beibehalten: `Proxy_Output/mnt/Aufnahmen/<Pfad>/<Name>.<ext>.mov` als 1:1-Spiegel und dieselbe Liste der Videoendungen.

## 9. Kurzfassung

| Nr. | Änderung | Warum |
|---|---|---|
| M1 | Teildatei `.teil` mit `-f mov`, erst nach Prüfung umbenennen | halbe Dateien gelten heute als fertig |
| M2 | Rückgabewerte auswerten, 0/1/2 | Fehler bleiben heute unbemerkt |
| M3 | Laufzeit, Spuren, Auflösung prüfen | Nachweis, bevor Originale gelöscht werden |
| M4 | Protokoll-CSV je Auftrag | Grundlage für Status und Löschfreigabe im Werkzeug |
| M5 | Auftragsdatei, Standardeingabe schützen | Schnittstelle zum Werkzeug, sonst endet der Lauf still nach der ersten Datei |
| M6 | `--nur-pruefen` | Bestand in `h264_archiv` nachträglich prüfen |
| M7 | `00_`/`01_` nur am ersten Ordner prüfen | Dateien mit `00_` im Namen fehlen heute still |
| M8 | Image mit Digest festlegen | gleiche Art der Dateien über Jahre |
| M9 | `2775`, Gruppe `Firma`, kein root, gezielte Einbindungen | Rechte wie im übrigen `Aufnahmen`, Originale geschützt |
| M10 | Profilkennung im Protokoll | später nachvollziehbar, welche Einstellungen galten |
| M11 | Bash-Array statt `eval` | Sonderzeichen im Namen |
| M12 | `trap` mit `docker stop` | Container läuft sonst nach dem Abbruch weiter |
| M13 | `flock` | keine zwei Läufe gleichzeitig |
| M14 | freien Platz prüfen | Platte voll mitten in der Datei |
| M15 | `systemd-run`, Zeitstempel, Zusammenfassung | Betrieb auf ELSA |
| M16 | Änderungszeit übernehmen (Empfehlung) | Datum der Aufnahme bleibt sichtbar |
