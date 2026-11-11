# Team Beinert – Proxy-Skript v5 und Archivskript

Werkzeug-Repository für den Strang **PX**: Proxy-Skript v5 (ersetzt `proxy_conv_docker_v4.sh` auf ELSA, Maßnahme M-01) und später das Archivskript (Maßnahme M-39). Auftraggeber ist Michl (Michael Mattausch, Geschäftsführer, GitHub `mmattausch`).

Der aktuelle Arbeitsplan steht in `IMPLEMENTATION_PLAN.md`.

## Firmenwissen

Ist-Stand, Beschlüsse und Arbeitsregeln der IT von Team Beinert liegen im Repository
`teambeinert_IT_wissen`, lokal unter `../teambeinert_IT_wissen`.

Vor Entwurfsentscheidungen lesen:
- `../teambeinert_IT_wissen/docs/arbeitsregeln.md`
- `../teambeinert_IT_wissen/docs/entscheidungen.md`
- `../teambeinert_IT_wissen/docs/themen/proxy-archiv-kontext.md` (zuerst)
- `../teambeinert_IT_wissen/docs/themen/proxy-und-archivskript.md`
- `../teambeinert_IT_wissen/docs/themen/z420-laufwerk-r.md`
- `../teambeinert_IT_wissen/docs/themen/sicherung-lto-archiv.md`
- `../teambeinert_IT_wissen/docs/referenz/` (v4 im Ist-Stand, nur zum Nachlesen; enthält die Sicherheitslücke)

Erkenntnisse aus der Umsetzung, die über dieses Werkzeug hinaus gelten (ein System
verhält sich anders als beschrieben, ein Beschluss von Michl, eine neue offene Frage),
dort in der passenden Datei nachtragen und als eigenen Commit im Wissens-Repository
ablegen. Nicht hier duplizieren.

## Arbeitsregeln

Übernommen aus `../teambeinert_IT_wissen/docs/arbeitsregeln.md`, Stand 11.11.2026. Bei Abweichungen gilt die Fassung im Wissens-Repository.

### Grundsätze von Michl

- **Erst Daten aufnehmen und prüfen, dann ändern.**
- **Befehle mit Änderungswirkung** auf ELSA, freenasbackup, dem Z420, der FRITZ!Box, bei Hetzner oder anderen Systemen gibt Michl selbst ein. Lesende Abfragen per SSH sind in Ordnung.
- **Kein Skript löscht je Originale.** Gelöscht wird erst nach bestandener Prüfung (bei Bändern: nach bestandener Bandprüfung), von Michl.
- **Keine Passwörter, Tokens oder Schlüssel** in Dokumente, Repositories oder das Wiki. Alles in 1Password.
- **Jede Änderung an Systemen** gehört ins Änderungsprotokoll der IT-Dokumentation (`../teambeinert_IT_wissen/docs/it-dokumentation.md`, Abschnitt 15). Das ist seit 11.11.2026 die einzige gepflegte Fassung; die Datei auf Michls Mac unter `OUTPUTS/IT-Dokumentation/` ist eingefroren. Vor dem Ändern `git pull`, nur gezielt ändern.
- **Praktisch und wartbar vor elegant.** Lösungen sollen auch in Jahren noch pflegbar sein.
- **Nutzersicht mitdenken:** Lösungen dürfen für die Kollegen nicht technisch komplex werden.
- Knappe, sachliche Kommunikation. Risiken eigenständig einordnen und Lösungen vorschlagen, nicht nur Fakten sammeln.
- Doku und Oberflächen auf Deutsch, Umlaute ausgeschrieben.
- `PRIV*`-Bänder sind privat: nie einlesen, nie anzeigen, nie auswerten.

### Technische Stolpersteine

- **Lange Läufe auf ELSA mit `systemd-run --unit=<name>` starten**, nie in tmux oder mit `nohup` unter `sudo -i`. Grund: sudo protokolliert auf ELSA jeden Unterbefehl (`Defaults log_subcmds`) und überwacht dafür jeden Programmstart per seccomp und ptrace. Endet die sudo-Sitzung, scheitert jeder weitere Programmstart mit `Function not implemented`. Am 03.11.2026 hat das den Archiv-Umzug nach 155 von 615 Dateien gestoppt.
- **zsh auf Michls Mac:** keine Kommentarzeilen in Befehlsblöcke, die er einfügen soll.
- **Plattennamen (`sdX`) ändern sich bei Neustarts.** Maßgeblich sind Seriennummern.
- **Hetzner-Server per SSH nur aus dem Büro** (Firewall). Unterwegs über WireGuard mit Split Tunnel, SSH auf die IPv4-Adressen, weil IPv6 am Tunnel vorbeiläuft.
- **ZFS-Refquota:** Es zählt `referenced`, nicht `used`. `used` bleibt hoch, solange Snapshots verschobene Dateien halten.
- **SMB-Datasets auf ELSA mit NFSv4-ACL** (`aclmode=restricted`) lehnen `chmod` ab. In Python deshalb `shutil.copyfile` statt `copy2`/`move`, Eigentümer danach setzen.
- **TrueNAS-Apps** laufen üblicherweise als Benutzer `apps` (UID/GID 568). Die Gruppe `Firma` hat GID 1003.
- **Daten von Apps auf ELSA** gehören unter `Container_space/apps/…` (eigener Host-Pfad, kein ixVolume), damit sie in Snapshot und Replikation liegen.
- **Für neue Dienste kein zusätzlicher Hetzner-Server.** Schon die kleinste Maschine samt IP ist zu teuer, lieber einen bestehenden hochstufen (Beschluss 09.11.2026).
- **Feste Versionen** bei Images, keine automatischen Updates. Watchtower läuft auf ELSA mit `--label-enable` und aktualisiert nur `chaoskontrolleur`.

### Strang

Dieses Repository gehört zum Strang `PX` (Proxy-Skript v5, Archivskript, Laufwerk `R:` am Z420). Bandkatalog, Bandaufträge und Sicherungskonzept gehören zu `BK`; Änderungen an der Schnittstelle zum Werkzeug „Bandarchiv“ mit BK abstimmen.

## Feste Randbedingungen für den Code

- Kein `eval`, keine Befehle als zusammengesetzte Strings. Dateinamen aus `Aufnahmen` gelten als nicht vertrauenswürdige Eingabe.
- `Aufnahmen/00_*` und `Aufnahmen/01_*` sowie alles unter `Proxies/` werden übersprungen. Diese Regel nicht ändern (Sammelordner `01_zum_Band` des Bandarchivs).
- Keine Pakete auf dem TrueNAS-Host installieren.
- ffmpeg läuft überall im Container `linuxserver/ffmpeg` mit festem Digest, auf ELSA wie am Schnittrechner (Docker Desktop). Kein eigener ffmpeg-Build, kein `ffmpeg.exe`.
- Das Proxy-Skript läuft auch am Windows-Schnittrechner (Aufruf mit einem Ordnerpfad, nur `Proxies/` wird geschrieben). Ein Code für beide Betriebsarten, keine zweite Fassung. Prozesspriorität nicht verändern.
- Abweichungen vom bisherigen Konzept ausdrücklich als solche benennen, nie stillschweigend einbauen.
- Code und Tests entstehen hier; auf ELSA ausgerollt wird nur von Michl.
