# Einrichtung auf ELSA: Proxy-Skript v5 (und Archivskript)

Stand: 14.11.2026 · für Michl · Strang PX, Maßnahmen M-01 und M-39

Alle Befehle mit Änderungswirkung gibt Michl selbst ein. Die Befehlsblöcke enthalten keine Kommentarzeilen und werden vom Mac aus abgesetzt (`ssh -t` fragt nach dem sudo-Passwort).

Voraussetzung: Die Tests sind bestanden (`docs/Testnachweis.md`): v5 liefert für alle Kameras dieselben Proxys wie v4. Nicht zwischen 19:30 und 21:00 arbeiten, damit nichts mit dem Abendlauf um 20:00 zusammenfällt.

---

## Entscheidung vorab: Unter welchem Benutzer laufen die Container?

Heute laufen v4 und der Container als root; alle Proxys gehören root.

| Möglichkeit | Folge |
|---|---|
| **A. Wie bisher, root** (`CONTAINER_USER` leer) | Keine weitere Einrichtung. Proxys gehören weiter root, wie heute. Die Sicherheitslücken (a) bis (e) sind trotzdem geschlossen: kein `eval`, Quelle nur lesend, Teildatei, Sperre. |
| B. Eigener Benutzer (Änderungsliste M9) | Vorher einen Dienstbenutzer in der Gruppe `Firma` anlegen und prüfen, dass er in `Proxy_Output/mnt/Aufnahmen` schreiben darf. Die Kopie nach `Proxies/` macht das Skript selbst (als root); dafür bräuchte es zusätzlich ein `chown`. |

**Empfehlung: A zum Start.** So wechselt beim Umstieg nur das Skript, nicht zusätzlich die Rechte. B als eigener Schritt danach (offen, siehe Abschnitt 9). Das ist eine bewusste Abweichung von M9 für den Start.

---

## 1. Code nach ELSA kopieren

Nach `/mnt/Mirror_2x8TB/Proxy_Output/v5/`, neben die alten Skripte. Dort ist Ausführen erlaubt (anders als in `/tmp`). Die alten Skripte bleiben unverändert liegen.

```bash
ssh mmattausch@192.168.23.8 mkdir -p /mnt/Mirror_2x8TB/Proxy_Output/v5 /mnt/Mirror_2x8TB/Proxy_Output/_protokolle
```

```bash
rsync -a --delete ~/code/teambeinert_proxy_archiv/proxy_v5.sh ~/code/teambeinert_proxy_archiv/archiv_h264.sh ~/code/teambeinert_proxy_archiv/lib mmattausch@192.168.23.8:/mnt/Mirror_2x8TB/Proxy_Output/v5/
```

Stand festhalten (Commit, der auf ELSA liegt):

```bash
git -C ~/code/teambeinert_proxy_archiv rev-parse --short HEAD
```

Die Ausgabe kommt ins Änderungsprotokoll (Abschnitt 8).

---

## 2. Leere Proxys aus der v4-Zeit suchen

v4 hinterlässt bei gescheitertem ffmpeg leere Dateien (0 Byte), die als fertig gelten (Befund 11). Auch v5 hält sie für vorhanden, solange beide Kopien da sind. Deshalb vorher suchen (nur lesend):

```bash
ssh mmattausch@192.168.23.8 "find /mnt/Aufnahme_mirror/Aufnahmen -path '*/Proxies/*' -name '*.mov' -size 0; find /mnt/Mirror_2x8TB/Proxy_Output/mnt/Aufnahmen -name '*.mov' -size 0"
```

Die Liste an Claude geben. Was dort steht, löscht Michl; v5 rechnet diese Proxys beim nächsten Lauf neu. Wenn die Liste leer ist: weiter mit Schritt 3.

---

## 3. Trockenlauf (ändert nichts)

Zeigt, was der Abendlauf tun würde. Ausgabe in eine Datei:

```bash
ssh -t mmattausch@192.168.23.8 sudo systemd-run --collect --wait --unit=proxy-v5-trocken -p StandardOutput=file:/mnt/Mirror_2x8TB/Proxy_Output/_protokolle/trocken.txt /usr/bin/bash /mnt/Mirror_2x8TB/Proxy_Output/v5/proxy_v5.sh --trocken
```

```bash
ssh mmattausch@192.168.23.8 tail -15 /mnt/Mirror_2x8TB/Proxy_Output/_protokolle/trocken.txt
```

Erwartet: fast alles `vorhanden`; `umrechnen` nur für neue Aufnahmen ohne Proxy; `kopieren`, wo eine der beiden Kopien fehlt. Die Zusammenfassung am Ende gibt die Zahlen. Bei vielen unerwarteten `umrechnen` oder `kopieren`: anhalten und mit Claude ansehen.

---

## 4. Prüflauf über einen Teil des Bestands (ändert nichts)

Prüft vorhandene Proxys gegen ihr Original (Laufzeit, Bild, Ton). Für ganz `Aufnahmen` würde das viele Stunden dauern (jede Datei mehrere Container-Aufrufe); deshalb zuerst ein Ordner, z. B. der Testordner. Er enthält zwei abgebrochene Proxys, die gefunden werden müssen.

```bash
ssh -t mmattausch@192.168.23.8 sudo systemd-run --collect --unit=proxy-v5-pruefen /usr/bin/bash /mnt/Mirror_2x8TB/Proxy_Output/v5/proxy_v5.sh --nur-pruefen /mnt/Aufnahme_mirror/Aufnahmen/2025-03-04_PROXY
```

Ergebnis: `/mnt/Mirror_2x8TB/Proxy_Output/_protokolle/pruefung_<Zeit>.csv`. Erwartet: zwei `Fehler` in `Ordner mit Leerzeichen`, sonst `vorhanden_ok`.

Ein vollständiger Prüflauf über `Aufnahmen` ist sinnvoll, aber nicht nötig für den Umstieg; am besten an einem Wochenende (gleicher Befehl ohne Ordner am Ende).

---

## 5. Erster echter Lauf von Hand

Macht genau das, was später der Cronjob tut, nur sofort und mit Protokoll im Journal:

```bash
ssh -t mmattausch@192.168.23.8 sudo systemd-run --collect --unit=proxy-v5-lauf /usr/bin/bash /mnt/Mirror_2x8TB/Proxy_Output/v5/proxy_v5.sh
```

Wenn nichts zu tun ist, dauert er Sekunden bis wenige Minuten (v4 brauchte 12 Minuten für „nichts“). Ergebnis: `/mnt/Mirror_2x8TB/Proxy_Output/_protokolle/lauf_<Zeit>.csv` (nur, wenn etwas gerechnet, kopiert oder ein Fehler gemeldet wurde).

```bash
ssh mmattausch@192.168.23.8 ls -lt /mnt/Mirror_2x8TB/Proxy_Output/_protokolle/
```

---

## 6. Cronjob umstellen

TrueNAS-Oberfläche: **System → Erweitert (Advanced) → Cron-Aufträge (Cron Jobs)**, den bestehenden Proxy-Auftrag bearbeiten.

| Feld | Bisher | Neu |
|---|---|---|
| Befehl | `/usr/bin/find /mnt/Aufnahme_mirror/Aufnahmen/ -type f ! -name ".*" \( -iname "*.mp4" -o -iname "*.mxf" -o -iname "*.mov" -o -iname "*.mpeg" -o -iname "*.avi" -o -iname "*.mts" \) -print0 \| /usr/bin/xargs -0 -n 1 -P 3 /mnt/Mirror_2x8TB/Proxy_Output/proxy_conv_docker_v4.sh > /mnt/Mirror_2x8TB/Proxy_Output/log_proxy_Elsa.log 2>&1` | `/usr/bin/bash /mnt/Mirror_2x8TB/Proxy_Output/v5/proxy_v5.sh > /mnt/Mirror_2x8TB/Proxy_Output/log_proxy_v5.log 2>&1` |
| Benutzer | root | root (unverändert) |
| Zeit | täglich 20:00 | unverändert |

Die alte Befehlszeile für den Rückweg aufheben (sie steht auch hier).

v5 sucht selbst, rechnet drei Dateien gleichzeitig wie bisher und nimmt nur Dateien, die seit 120 Minuten unverändert sind.

---

## 7. Kontrolle in den ersten Tagen

Am Morgen nach jedem der ersten drei Abendläufe:

```bash
ssh mmattausch@192.168.23.8 "tail -12 /mnt/Mirror_2x8TB/Proxy_Output/log_proxy_v5.log; ls -lt /mnt/Mirror_2x8TB/Proxy_Output/_protokolle/ | head -5"
```

Die letzten Zeilen des Logs sind die Zusammenfassung (`ok`, `kopiert`, `vorhanden`, `Fehler` …). Bei `Fehler` stehen die Gründe weiter oben im Log und im Protokoll `lauf_<Zeit>.csv`. Dazu einmal einen frischen Proxy in DaVinci per „Link Proxy“ einbinden und ansehen.

**Rückweg**, falls etwas nicht stimmt: im Cronjob wieder die alte Befehlszeile eintragen. v5 hinterlässt nur fertige, geprüfte Proxys an denselben Orten wie v4 und seine Protokolle in `_protokolle/`; v4 kann sofort weitermachen.

---

## 8. Dokumentation

Nach der Umstellung (Claude formuliert die Einträge, Michl bestätigt):
- Änderungsprotokoll `docs/it-dokumentation.md`, Abschnitt 15: Datum, „Proxy-Cronjob von v4 auf v5 umgestellt“, Pfad `/mnt/Mirror_2x8TB/Proxy_Output/v5/`, Commit aus Schritt 1, Container weiter als root.
- `docs/massnahmen.md`: M-01 auf erledigt, sobald drei Abendläufe ohne unerklärte Fehler gelaufen sind.
- IT-Dokumentation Abschnitt 9, Punkt 21 (Beschreibung des Proxy-Skripts) auf v5 anpassen.

---

## 9. Danach (eigene Schritte)

- **Rechte (M9):** eigener Benutzer für die Container, siehe Entscheidung oben.
- **Alarm bei Fehlern:** Ob TrueNAS bei Rückgabewert 1 eine E-Mail schickt, hängt von den Einstellungen des Cronjobs ab und ist nicht geprüft. Der vorgesehene Weg ist ein Push an Uptime Kuma; eigener Schritt.
- **Archivskript in Betrieb nehmen:** Der Code liegt nach Schritt 1 schon unter `v5/archiv_h264.sh`. Statt `find … | xargs -P 3 archiv_h264.sh` gibt es jetzt `--ordner`; es macht dasselbe (drei Dateien gleichzeitig) und läuft als eigene Unit, bricht also beim Ende der SSH-Sitzung nicht ab. Den Ordnerpfad anpassen; der ganze Befehl steht in einfachen Anführungszeichen, damit Leerzeichen im Pfad heil ankommen:

  ```bash
  ssh -t mmattausch@192.168.23.8 'sudo systemd-run --collect --unit=archiv-ordner /usr/bin/bash /mnt/Mirror_2x8TB/Proxy_Output/v5/archiv_h264.sh --ordner "/mnt/Aufnahme_mirror/Aufnahmen/<Projekt>/<Unterordner>"'
  ```

  Fortschritt mit `journalctl -u archiv-ordner -f`, Ergebnis je Datei in `h264_archiv/_protokolle/einzel_<Datum>.csv`. Vor dem ersten Löschen von Originalen: Prüflauf über den Bestand in `h264_archiv` (646 Dateien); Anleitung folgt mit dem Werkzeug „Bandarchiv“.
- **Schnittrechner:** `proxy.bat` und Test, sobald Docker Desktop dort läuft.
