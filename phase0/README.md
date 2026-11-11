# Phase 0: Daten aufnehmen

Stand: 11.11.2026 · gehört zu `IMPLEMENTATION_PLAN.md`, Abschnitt 7.

Alles hier ist **nur lesend**. Auf ELSA wird ausschließlich nach `/tmp/phase0` geschrieben. Es wird kein Image geholt (`--pull never`), nichts installiert, nichts geändert.

Die Befehlsblöcke enthalten keine Kommentarzeilen und lassen sich so in die Shell einfügen.

---

## A. ELSA, kurze Abfragen (wenige Sekunden)

Per SSH auf ELSA, als root (`sudo -i` ist hier in Ordnung, weil nichts lange läuft).

```bash
mkdir -p /tmp/phase0
cd /tmp/phase0
sha256sum /mnt/Mirror_2x8TB/Proxy_Output/proxy_conv_docker_v4.sh > v4_sha256.txt
ls -l --time-style=long-iso /mnt/Mirror_2x8TB/Proxy_Output/*.sh > skripte_liste.txt
cp /mnt/Mirror_2x8TB/Proxy_Output/archiv_h264.sh archiv_h264.IST-STAND.sh.txt
docker image ls --digests linuxserver/ffmpeg > image_liste.txt
docker image inspect linuxserver/ffmpeg --format '{{.Id}} {{index .RepoDigests 0}} {{.Created}}' > image_digest.txt
docker run --rm --pull never linuxserver/ffmpeg -hide_banner -version > ffmpeg_version.txt 2>&1
docker run --rm --pull never --entrypoint bash linuxserver/ffmpeg -c 'bash --version | head -1; find --version | head -1; xargs --version | head -1; flock --version; df --version | head -1; stat --version | head -1; command -v shuf awk sed grep' > image_werkzeuge.txt 2>&1
docker image inspect linuxserver/ffmpeg --format 'Entrypoint {{.Config.Entrypoint}} Cmd {{.Config.Cmd}} User {{.Config.User}}' >> image_werkzeuge.txt
python3 --version > host_python.txt 2>&1
for d in /mnt/Aufnahme_mirror/Aufnahmen /mnt/Mirror_2x8TB/Proxy_Output /mnt/Mirror_2x8TB/Proxy_Output/mnt/Aufnahmen /mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup /mnt/Aufnahme_mirror/Aufnahmen/00_to_Backup/h264_archiv; do echo "=== $d"; stat -c '%U(%u):%G(%g) %a %n' "$d"; nfs4xdr_getfacl "$d" 2>&1 | head -20; getfacl -p "$d" 2>&1 | head -12; done > rechte.txt
find /mnt/Aufnahme_mirror/Aufnahmen -maxdepth 3 -type d -name Proxies | head -1 | while IFS= read -r p; do echo "=== $p"; stat -c '%U(%u):%G(%g) %a %n' "$p"; ls -ln "$p" | head -5; done >> rechte.txt
zfs get -H -o name,property,value casesensitivity,aclmode,acltype Aufnahme_mirror/Aufnahmen Mirror_2x8TB/Proxy_Output > zfs_eigenschaften.txt 2>&1
df -h /mnt/Aufnahme_mirror/Aufnahmen /mnt/Mirror_2x8TB/Proxy_Output > platz.txt
tail -100 /mnt/Mirror_2x8TB/Proxy_Output/log_proxy_Elsa.log > log_v4_ende.txt
ls -l --time-style=long-iso /mnt/Mirror_2x8TB/Proxy_Output/log_proxy_Elsa.log >> log_v4_ende.txt
ls -l /tmp/phase0
```

Falls `zfs get` andere Dataset-Namen braucht: `zfs list -o name,mountpoint | grep -E 'Aufnahmen|Proxy_Output'` zeigt die richtigen.

Dazu bitte von Hand notieren:
- Die Zeile des Proxy-Cronjobs aus der TrueNAS-Oberfläche (System → Erweitert → Cron-Aufträge), mit Benutzer.
- **Wie wird `archiv_h264.sh` heute aufgerufen?** (Befehlszeile, von wem, wie oft)

---

## B. ELSA, lange Abfragen (Stunden, im Hintergrund)

Durchsucht ganz `Aufnahmen` (Dateiliste, Endungen, Namenspaare, Platz der `Proxies/`, Umfang `h264_archiv`) und nimmt eine ffprobe-Stichprobe von 100 Dateien. Läuft per `systemd-run`, damit es das Ende der SSH-Sitzung übersteht.

Vom Mac aus das Skript nach ELSA kopieren (Benutzer anpassen):

```bash
scp ~/code/teambeinert_proxy_archiv/phase0/phase0_lang.sh mmattausch@192.168.23.8:/tmp/phase0_lang.sh
```

Auf ELSA als root starten:

```bash
systemd-run --unit=phase0-lang /usr/bin/bash /tmp/phase0_lang.sh
```

Fortschritt ansehen:

```bash
cat /tmp/phase0/lang_status.txt
```

```bash
systemctl status phase0-lang --no-pager
```

Fertig, wenn in `lang_status.txt` „Ende“ steht.

---

## C. Ergebnisse auf den Mac holen

```bash
mkdir -p ~/code/teambeinert_proxy_archiv/phase0/ergebnisse
```

```bash
scp -r 'mmattausch@192.168.23.8:/tmp/phase0/*' ~/code/teambeinert_proxy_archiv/phase0/ergebnisse/
```

`phase0/ergebnisse/` steht in `.gitignore`, weil die Listen Projekt- und Kundennamen enthalten. Ich werte sie aus; `archiv_h264.IST-STAND.sh.txt` lege ich danach ins Wissens-Repo unter `docs/referenz/`.

Wenn alles ausgewertet ist, kann `/tmp/phase0` auf ELSA gelöscht werden (macht Michl).

---

## D. Schnittrechner

**Fragen** (Michl oder ein Kollege beantwortet sie):

1. Welche Rechner kommen in Frage? Je Rechner: Windows-Version, CPU, RAM, freier Platz auf dem Laufwerk für Aufnahmen.
2. Ist Docker Desktop schon installiert? Läuft WSL2? (In PowerShell: `wsl --status` und `docker version`.)
3. Docker Desktop ist für kleine Firmen kostenlos; die aktuellen Lizenzbedingungen bitte einmal gegen die Firmengröße prüfen.
4. Womit werden Aufnahmen nach `Aufnahmen` auf ELSA kopiert: Explorer, TeraCopy, robocopy, anderes?
5. Wie binden die Schnittplätze die Proxys ein (DaVinci Resolve Free oder Studio, Version; über den Ordner `Proxies/`)?

**Messung Altersgrenze** (Plan 0.11): Eine große Videodatei (mehrere GB) so nach `Aufnahmen` kopieren, wie es üblich ist, in einen Testordner. Während des Kopierens auf ELSA:

```bash
while true; do stat -c '%y  %z  %s  %n' /mnt/Aufnahme_mirror/Aufnahmen/<Testordner>/<Datei>; sleep 10; done
```

Mit Strg+C beenden, wenn das Kopieren fertig ist, und die Ausgabe aufheben. Die erste Zeitspalte ist die Änderungszeit, die zweite die Statusänderungszeit. Interessant ist, ob die Änderungszeit während des Kopierens die aktuelle Uhrzeit zeigt oder schon die alte Zeit des Originals. Wenn mehrere Kopierprogramme genutzt werden, je eines messen.

**Testlauf Docker unter Windows** (Plan 0.12): kommt, sobald Docker Desktop läuft. Den Befehl schreibe ich dann passend zum Rechner.
