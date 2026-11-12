# Schnittrechner: Erhebung für das neue Proxy-Skript

Stand: 11.11.2026 · von Michl

Wir wollen Proxys künftig auch direkt am Schnittrechner erzeugen können (für eilige Produktionen). Dafür brauchen wir ein paar Angaben zu den Rechnern. Alles hier **liest nur**: Es wird nichts geändert und nichts installiert, außer in Schritt 4 (nur nach Rücksprache).

---

## 1. Erhebung je Rechner (automatisch)

Auf jedem Schnittrechner, der in Frage kommt:

1. Startmenü öffnen, **PowerShell** eingeben und öffnen (normale Rechte genügen, nicht „als Administrator“).
2. Den ganzen grauen Block unten kopieren und in das PowerShell-Fenster einfügen (Rechtsklick fügt ein), dann Enter.
3. Nach ein paar Sekunden geht im Editor die Datei `schnittrechner_erhebung.txt` auf. Sie liegt auf dem Desktop. **Diese Datei an Michl schicken.**

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

Fehlermeldungen in der Datei wie „docker wird nicht erkannt“ sind **kein Problem**, das ist dann einfach die Antwort.

**Wichtig:** Falls irgendwann ein Fenster fragt „Drücken Sie eine beliebige Taste, um … zu installieren“, **nichts drücken**, sondern Esc oder Strg+C. (In einer früheren Fassung dieses Blocks konnte das bei fehlendem WSL passieren; diese Fassung fragt nicht mehr.)

---

## 2. Drei kurze Fragen

Bitte kurz per Nachricht beantworten:

1. Welche Schnittrechner kommen für die Proxy-Erzeugung in Frage?
2. Womit kopierst du Aufnahmen auf den Server nach `Aufnahmen`: Explorer (Ziehen und Ablegen), TeraCopy, robocopy oder etwas anderes?
3. Wie bindest du die Proxys in DaVinci Resolve ein: über den Ordner `Proxies/` neben den Aufnahmen, von Hand verknüpft oder automatisch?

---

## 3. Messung beim Kopieren (zusammen mit Michl)

Dafür bitte kurz bei Michl melden, er schaut währenddessen auf dem Server zu.

1. Eine große Videodatei (mehrere GB) so auf den Server nach `Aufnahmen` kopieren, wie du es sonst auch machst, in einen Testordner (z. B. `Aufnahmen\Kopiertest`).
2. Michl lässt währenddessen auf dem Server alle 10 Sekunden die Zeitstempel der Datei anzeigen:

```bash
while true; do stat -c '%y  %z  %s  %n' /mnt/Aufnahme_mirror/Aufnahmen/Kopiertest/<Datei>; sleep 10; done
```

Wenn du mehrere Kopierprogramme benutzt, bitte mit jedem einmal.

---

## 4. Testlauf mit Docker (nur nach Rücksprache mit Michl)

Nur auf einem Rechner, auf dem **Docker Desktop schon läuft** (steht in der Datei aus Schritt 1). Der erste Befehl lädt rund 730 MB herunter.

Vorbereitung:

1. Einen Ordner `D:\Proxytest` anlegen. Wenn es kein Laufwerk `D:` gibt, ein anderes nehmen und in der zweiten Zeile des Blocks den Pfad anpassen.
2. Eine typische Aufnahme hineinkopieren, z. B. eine FX3-Datei von einigen GB, und in `test.MP4` umbenennen. **Bitte keine echten Projektordner nehmen, nur diesen Testordner.**

Dann PowerShell öffnen und den Block einfügen:

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

Das dauert je nach Datei ein paar Minuten. Danach steht das Ergebnis in `D:\Proxytest\ergebnis.txt`. **Diese Datei an Michl schicken.** Der Ordner `D:\Proxytest` kann danach gelöscht werden.

Danke!
