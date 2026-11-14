# Tests

Stand: 13.11.2026

| Skript | Was | Wo |
|---|---|---|
| `erzeuge_testdateien.sh <Ordner>` | erzeugt 45 kurze Testdateien (Namen, Ton, Timecode, Formate, Defekte, Ausschlüsse) | Mac (Colima) oder ELSA |
| `lauf_tests.sh` | Ablauftests von `proxy_v5.sh` mit diesen Dateien (49 Prüfungen) | Linux mit Docker: Colima-VM oder ELSA |
| `v4_vergleich.sh` | vergleicht die ffmpeg-Argumente von v4 und v5 Datei für Datei (v4 mit `docker`-Attrappe) | Colima-VM |
| `korpus_vergleich.sh` | v4 und v5 rechnen den Testkorpus `Aufnahmen/2025-03-04_PROXY`, Vergleich von Bild und Ton per `framemd5` | **ELSA** |

Auf dem Mac laufen die Tests in der Colima-VM (macOS hat nur Bash 3.2):

```bash
colima ssh -- bash -c 'cd ~/code/teambeinert_proxy_archiv && tests/lauf_tests.sh'
```

Testdaten liegen in `tests/daten/` (nicht im Repository).

---

## Testkorpus auf ELSA (`korpus_vergleich.sh`)

Liest den Testordner `Aufnahmen/2025-03-04_PROXY` nur. Schreibt ausschließlich nach `/mnt/Mirror_2x8TB/Proxy_Output/_test` (rund 200 MB). v4 läuft als echtes `proxy_conv_docker_v4.sh`; in einer Testkopie sind nur die drei Pfadvariablen `basedir`, `proxydest` und `proxydestfile` auf das Testverzeichnis umgestellt. Das Skript prüft vorher die Prüfsumme von v4 und dass v4 und v5 dasselbe Image nutzen.

Dauer: rund 20 Minuten (63 Dateien, jede zweimal umgerechnet; v4 allein brauchte am 13.11.2026 knapp 10 Minuten). Nicht um 20:00 starten, damit es nicht mit dem Abendlauf zusammenfällt.

**1. Code nach ELSA kopieren** (vom Mac, ohne Testdaten). `/tmp` ist auf ELSA mit `noexec` eingehängt; die Skripte werden deshalb immer über `bash` gestartet, das ist so berücksichtigt.

```bash
rsync -a --delete --exclude tests/daten --exclude phase0/ergebnisse --exclude .git ~/code/teambeinert_proxy_archiv/ mmattausch@192.168.23.8:/tmp/proxy_v5/
```

**2. Testverzeichnis anlegen** (vom Mac, fragt nach dem sudo-Passwort):

```bash
ssh -t mmattausch@192.168.23.8 sudo mkdir -p /mnt/Mirror_2x8TB/Proxy_Output/_test
```

**3. Starten:**

```bash
ssh -t mmattausch@192.168.23.8 sudo systemd-run --collect --unit=proxy-v5-korpus /usr/bin/bash /tmp/proxy_v5/tests/korpus_vergleich.sh
```

Meldet `systemd-run`, die Unit sei „already loaded“, hängt noch eine alte Unit vom vorigen Lauf. Dann einmal `ssh -t mmattausch@192.168.23.8 sudo systemctl reset-failed proxy-v5-korpus` und erneut starten. Mit `--collect` passiert das künftig nicht mehr.

**4. Fortschritt ansehen** (Strg+C beendet nur das Ansehen):

```bash
ssh -t mmattausch@192.168.23.8 sudo journalctl -u proxy-v5-korpus -f
```

Fertig, wenn eine Zeile „Fertig. Gleich: …“ erscheint.

**5. Ergebnis holen** (Tabelle und Protokoll des Laufs; lesbar ohne sudo):

```bash
scp 'mmattausch@192.168.23.8:/mnt/Mirror_2x8TB/Proxy_Output/_test/vergleich_*' ~/code/teambeinert_proxy_archiv/phase0/ergebnisse/
```

Den Arbeitsordner `_test/lauf_<Zeit>` bitte erst löschen, wenn die Auswertung fertig ist; dort liegen die Fehlermeldungen je Datei.

Danach kann `/mnt/Mirror_2x8TB/Proxy_Output/_test` gelöscht werden (macht Michl), ebenso `/tmp/proxy_v5`.

**Ergebnis lesen:** Je Datei `gleich` (Bild und Ton bitgleich), `erklaert` (bekannter Fehler von v4, z. B. leere Datei bei gescheitertem ffmpeg) oder `ungleich` (muss untersucht werden). Spalte `pruefung_v5` zeigt, ob der v5-Proxy die Prüfung nach M3 besteht.

---

## Leere Proxys auf ELSA suchen (nur lesend)

Wenn ffmpeg scheitert, hinterlässt v4 einen leeren Proxy (0 Byte) an beiden Orten; er gilt danach als fertig und wird nie neu gerechnet. So findet man solche Fälle:

```bash
ssh mmattausch@192.168.23.8 "find /mnt/Aufnahme_mirror/Aufnahmen -path '*/Proxies/*' -name '*.mov' -size 0 | wc -l; find /mnt/Mirror_2x8TB/Proxy_Output/mnt/Aufnahmen -name '*.mov' -size 0 | wc -l"
```

Die erste Zahl sind leere lokale Proxys, die zweite leere zentrale.
