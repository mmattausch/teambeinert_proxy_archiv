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

Von Hand notiert (11.11.2026, erledigt): Cron-Zeile des Proxys und Aufruf von `archiv_h264.sh` stehen im Plan, Abschnitt 2. Der Cronjob läuft als root (Michl, 11.11.2026).

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

### D1. Erhebung je Schnittrechner (automatisch, nur lesend)

Auf jedem Rechner, der in Frage kommt, **PowerShell** öffnen (Startmenü → „PowerShell“, normale Rechte genügen) und den ganzen Block einfügen. Er ändert nichts, installiert nichts und schreibt nur die Datei `schnittrechner_erhebung.txt` auf den Desktop, die danach im Editor aufgeht. Die Datei an Michl schicken.

```powershell
$out = "$env:USERPROFILE\Desktop\schnittrechner_erhebung.txt"
& {
"=== Rechner"; $env:COMPUTERNAME; Get-Date -Format "yyyy-MM-dd HH:mm"
"=== Windows"; Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture | Format-List | Out-String
"=== CPU"; Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled | Format-List | Out-String
"=== RAM GB"; [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
"=== Hypervisor aktiv"; (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
"=== Grafik"; Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion | Format-List | Out-String
"=== Laufwerke"; Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 3,4 } | Select-Object DeviceID, VolumeName, FileSystem, @{n='GroesseGB';e={[math]::Round($_.Size/1GB)}}, @{n='FreiGB';e={[math]::Round($_.FreeSpace/1GB)}}, ProviderName | Format-Table -AutoSize | Out-String -Width 200
"=== Netzlaufwerke"; Get-SmbMapping -ErrorAction SilentlyContinue | Select-Object LocalPath, RemotePath, Status | Format-Table -AutoSize | Out-String -Width 200
"=== Netzwerk"; Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription, LinkSpeed | Format-Table -AutoSize | Out-String -Width 200
"=== WSL"; Get-AppxPackage -Name MicrosoftCorporationII.WindowsSubsystemForLinux -ErrorAction SilentlyContinue | Select-Object Name, Version | Format-List | Out-String; Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue | ForEach-Object { $_.GetValue('DistributionName') }
"=== Docker"; docker version 2>&1 | Out-String; docker image ls 2>&1 | Out-String
"=== Python und ffmpeg im Pfad"; Get-Command python, py, ffmpeg -ErrorAction SilentlyContinue | Select-Object Name, Source | Format-Table -AutoSize | Out-String -Width 200
"=== Programme"; Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'DaVinci|Resolve|TeraCopy|FastCopy|FreeFileSync|Docker|Python|Syncthing|Premiere' } | Select-Object DisplayName, DisplayVersion | Sort-Object DisplayName | Format-Table -AutoSize | Out-String -Width 200
} *>&1 | Out-File -FilePath $out -Encoding utf8
notepad $out
```

Daraus ergeben sich: Windows-Version, CPU, RAM, Grafikkarte, freier Platz je Laufwerk, verbundene ELSA-Freigaben, Netzwerkgeschwindigkeit, ob WSL2 und Docker Desktop da sind, ob Python oder ffmpeg installiert ist (ein Pfad mit `WindowsApps` ist nur der Platzhalter des Microsoft Store, kein echtes Python), installierte Version von DaVinci Resolve und vorhandene Kopierprogramme.

Fehlermeldungen in der Datei wie „docker wird nicht erkannt“ sind kein Problem, sondern die Antwort.

Korrigiert 12.11.2026: Die erste Fassung rief `wsl --list --verbose` auf. Ist WSL nicht installiert, bietet Windows dabei mit „beliebige Taste drücken“ die Installation an (auf VFX-WORKSTATION nach 60 s ohne Eingabe abgebrochen). Die WSL-Abfrage liest jetzt nur noch Paketliste und Registry.

### D2. Fragen, die kein Befehl beantwortet

1. Welche Rechner kommen für den Proxy-Betrieb in Frage?
2. Womit werden Aufnahmen nach `Aufnahmen` auf ELSA kopiert: Explorer, TeraCopy, robocopy, anderes?
3. Wie binden die Schnittplätze die Proxys in Resolve ein (über den Ordner `Proxies/`, von Hand verknüpft, automatisch)? Free oder Studio steht in D1 meist schon im Programmnamen.
### D3. Messung Altersgrenze (Plan 0.11)

Eine große Videodatei (mehrere GB) so nach `Aufnahmen` kopieren, wie es üblich ist, in einen Testordner. Während des Kopierens auf ELSA:

```bash
while true; do stat -c '%y  %z  %s  %n' /mnt/Aufnahme_mirror/Aufnahmen/<Testordner>/<Datei>; sleep 10; done
```

Mit Strg+C beenden, wenn das Kopieren fertig ist, und die Ausgabe aufheben. Die erste Zeitspalte ist die Änderungszeit, die zweite die Statusänderungszeit. Interessant ist, ob die Änderungszeit während des Kopierens die aktuelle Uhrzeit zeigt oder schon die alte Zeit des Originals. Wenn mehrere Kopierprogramme genutzt werden, je eines messen.

### D4. Testlauf Docker unter Windows (Plan 0.12)

Nur auf einem Rechner, auf dem Docker Desktop schon läuft (siehe D1), und erst nach Rücksprache mit Michl: Der erste Befehl lädt das Image (rund 730 MB) auf den Rechner.

Vorbereitung: einen Ordner `D:\Proxytest` anlegen (anderes Laufwerk geht auch, dann `$ordner` anpassen) und eine typische Aufnahme hineinkopieren, z. B. eine FX3-Datei von einigen GB, umbenannt in `test.MP4`.

```powershell
$img = "linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697"
$ordner = "D:\Proxytest"
docker pull $img
$groesse = (Get-Item "$ordner\test.MP4").Length
$lesen = Measure-Command { docker run --rm -v "${ordner}:/arbeit:ro" --entrypoint bash $img -c 'cat /arbeit/test.MP4 > /dev/null' }
$werkzeuge = docker run --rm -v "${ordner}:/arbeit" --entrypoint bash $img -c 'bash --version | head -1; find /arbeit -maxdepth 1 -type f -iname "*.mp4"; touch /arbeit/schreibtest && rm /arbeit/schreibtest && echo schreiben ok' 2>&1 | Out-String
$proxy = Measure-Command { docker run --rm -v "${ordner}:/arbeit" $img -nostdin -hide_banner -loglevel error -i /arbeit/test.MP4 -vf scale=-1:540 -pix_fmt yuv420p -map 0:v -map 0:a? -c:v libx264 -c:a aac -profile:v main -level 2.1 -preset veryfast -tune fastdecode -crf 21 -threads 4 -x264opts keyint=75 -f mov /arbeit/test_proxy.mov.teil }
$dauer = docker run --rm -v "${ordner}:/arbeit:ro" --entrypoint ffprobe $img -v error -show_entries format=duration -of csv=p=0 /arbeit/test.MP4
"Datei: {0:N0} MB, Laufzeit {1} s" -f ($groesse/1MB), $dauer | Tee-Object -FilePath "$ordner\ergebnis.txt"
"Lesen aus dem Container: {0:N1} s = {1:N0} MB/s" -f $lesen.TotalSeconds, (($groesse/1MB)/$lesen.TotalSeconds) | Tee-Object -FilePath "$ordner\ergebnis.txt" -Append
"Proxy erzeugen: {0:N1} s" -f $proxy.TotalSeconds | Tee-Object -FilePath "$ordner\ergebnis.txt" -Append
$werkzeuge | Tee-Object -FilePath "$ordner\ergebnis.txt" -Append
```

Ergebnis steht danach in `D:\Proxytest\ergebnis.txt`. Die Datei `test_proxy.mov.teil` ist der erzeugte Probeproxy, sie kann danach gelöscht werden. Der Ordner `D:\Proxytest` ist nur zum Testen da; bitte keine echten Projektordner nehmen.

---

## E. Testordner `Aufnahmen/2025-03-04_PROXY` (ELSA, nur lesend)

Untersucht je Originaldatei des Testordners Original, lokalen und zentralen Proxy (Spuren, Laufzeit, Größe, Datum). Dauert wenige Minuten. Schreibt nur `/tmp/phase0/korpus_ffprobe.txt`.

Vom Mac aus das Skript nach ELSA kopieren:

```bash
scp ~/code/teambeinert_proxy_archiv/phase0/korpus_ffprobe.sh mmattausch@192.168.23.8:/tmp/korpus_ffprobe.sh
```

Auf ELSA als root starten:

```bash
systemd-run --unit=phase0-korpus /usr/bin/bash /tmp/korpus_ffprobe.sh
```

Fertig, wenn die letzte Zeile mit „Ende:“ beginnt:

```bash
tail -3 /tmp/phase0/korpus_ffprobe.txt
```

Ergebnis auf den Mac holen:

```bash
scp mmattausch@192.168.23.8:/tmp/phase0/korpus_ffprobe.txt ~/code/teambeinert_proxy_archiv/phase0/ergebnisse/
```
