# Schnittrechner: Docker einrichten für das Proxy-Skript

Stand: 12.11.2026 · von Michl

Damit Proxys direkt am Schnittrechner entstehen können, braucht jeder Rechner **Docker Desktop**. Darin läuft dasselbe ffmpeg wie auf dem Server, sodass die Proxys überall gleich aussehen.

Die Einrichtung dauert je Rechner etwa 30–45 Minuten mit **zwei Neustarts**. Bitte nicht während eines laufenden Schnitts. Du brauchst ein **Konto mit Administratorrechten** auf dem Rechner.

Vorher schon erledigt sein sollte die Erhebung aus `Schnittrechner_Anleitung.md`, Schritt 1. Daraus wissen wir, ob die Virtualisierung an ist und ob WSL oder Docker schon da sind.

**Checkliste je Rechner** (abhaken und an Michl zurückmelden):

- [ ] 1. Virtualisierung im BIOS eingeschaltet
- [ ] 2. WSL2 installiert
- [ ] 3. Docker Desktop installiert
- [ ] 4. Docker Desktop eingestellt
- [ ] 5. Benutzer in der Gruppe `docker-users`
- [ ] 6. ffmpeg-Image geladen und geprüft
- [ ] 7. Testlauf, Ergebnis an Michl

---

## 1. Virtualisierung im BIOS einschalten

Nur nötig, wenn in der Erhebung `VirtualizationFirmwareEnabled : False` stand.

**Vorher prüfen:** Task-Manager öffnen (Strg+Umschalt+Esc) → **Leistung** → **CPU**. Rechts unten steht „Virtualisierung: **Aktiviert**“ oder „Deaktiviert“. Bei „Aktiviert“ gleich weiter zu Schritt 2.

**Hersteller der Hauptplatine herausfinden** (PowerShell, ändert nichts):

```powershell
Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product
```

**Ins BIOS:** Rechner neu starten und gleich nach dem Einschalten mehrmals **Entf** (bei manchen Platinen **F2**) drücken.

**Einstellung suchen:** Bei AMD-Prozessoren heißt sie **SVM Mode** (bei Intel **Intel Virtualization Technology** bzw. **VT-x**). Sie liegt je nach Hersteller etwa hier:

| Hersteller | Typischer Ort |
|---|---|
| ASUS | Advanced Mode (F7) → Advanced → CPU Configuration → **SVM Mode** |
| MSI | Advanced (F7) → OC → Advanced CPU Configuration → **SVM Mode** |
| Gigabyte | Tweaker → Advanced CPU Settings → **SVM Mode** |
| ASRock | Advanced → CPU Configuration → **SVM Mode** |

Auf **Enabled** stellen. **Sonst nichts verändern.** Mit **F10** speichern und neu starten.

**Danach prüfen:** Task-Manager → Leistung → CPU → „Virtualisierung: **Aktiviert**“.

---

## 2. WSL2 installieren

**PowerShell als Administrator** öffnen: Startmenü → „PowerShell“ eingeben → Rechtsklick → **Als Administrator ausführen**.

```powershell
wsl --install --no-distribution
```

Wenn die Meldung kommt, dass ein Neustart nötig ist: **neu starten**.

Nach dem Neustart wieder PowerShell als Administrator:

```powershell
wsl --update
```

```powershell
wsl --status
```

Bei `wsl --status` sollte „Standardversion: 2“ (bzw. „Default Version: 2“) stehen. Eine Linux-Distribution (Ubuntu o. Ä.) wird **nicht** gebraucht.

---

## 3. Docker Desktop installieren

1. Installationsprogramm **nur von der offiziellen Seite** laden: <https://www.docker.com/products/docker-desktop/> → „Download for Windows – AMD64“.
2. `Docker Desktop Installer.exe` starten (fragt nach Administratorrechten).
3. Im Installationsdialog: **„Use WSL 2 instead of Hyper-V“ angehakt lassen**. Eine Desktop-Verknüpfung ist egal.
4. Nach der Installation: **abmelden und wieder anmelden** (oder neu starten), wenn das Programm darum bittet.
5. Docker Desktop starten und die Bedingungen annehmen.
6. Die Frage nach Anmeldung bzw. Docker-Konto **überspringen** („Continue without signing in“ / „Skip“). Ein Konto wird nicht gebraucht. Fragebögen ebenfalls überspringen.

---

## 4. Docker Desktop einstellen

In Docker Desktop oben rechts auf das **Zahnrad** (Settings).

**General:**
- **Start Docker Desktop when you sign in to your computer:** **an**. Sonst müsste man Docker vor jedem Proxy-Lauf von Hand starten.
- **Send usage statistics:** **aus**.

**Software updates:**
- **Automatically check for updates:** **aus**.
- **Always download updates:** **aus**.

Grund: Bei uns gilt „feste Versionen, keine automatischen Updates“. Updates macht Michl bewusst.

Unten **Apply & restart**.

Andere Einstellungen (Ressourcen, Speicher, Erweiterungen) **nicht ändern**.

---

## 5. Benutzer in die Gruppe `docker-users`

Wer an diesem Rechner arbeitet, muss Docker benutzen dürfen. Der Benutzer, der installiert hat, ist schon drin; alle anderen müssen hinzugefügt werden.

PowerShell als Administrator, `<Benutzername>` durch den Windows-Anmeldenamen ersetzen (z. B. `tklotz`):

```powershell
net localgroup docker-users <Benutzername> /add
```

Prüfen, wer drin ist:

```powershell
net localgroup docker-users
```

Danach muss sich der Benutzer **einmal ab- und wieder anmelden**.

---

## 6. ffmpeg-Image laden und prüfen

**Normale PowerShell** (nicht als Administrator), Docker Desktop muss laufen (Wal-Symbol unten rechts in der Taskleiste):

```powershell
docker pull linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697
```

Das lädt rund 730 MB. Danach:

```powershell
docker run --rm linuxserver/ffmpeg@sha256:784db915924daf9081ab57b46b91d37610c60da5d9600ffd9855c7568fadc697 -hide_banner -version
```

Die erste Zeile muss lauten: `ffmpeg version 8.0`. Dann ist es genau dasselbe ffmpeg wie auf dem Server.

**Wichtig:** Immer diese lange Bezeichnung mit `@sha256:…` verwenden, nie nur `linuxserver/ffmpeg`. Sonst lädt Docker irgendwann eine neuere Fassung.

---

## 7. Testlauf

Steht in `Schnittrechner_Anleitung.md`, **Schritt 4** (Ordner `D:\Proxytest`, eine Testaufnahme, Block einfügen). Der Befehl `docker pull` darin ist nach Schritt 6 schon erledigt und geht dann sofort durch.

Die Datei `D:\Proxytest\ergebnis.txt` an Michl schicken, zusammen mit der abgehakten Checkliste und dem Rechnernamen.

---

## Wenn etwas nicht klappt

| Meldung | Ursache | Abhilfe |
|---|---|---|
| Docker Desktop: „Virtualization support not detected“ o. Ä. | SVM im BIOS aus | Schritt 1 |
| Docker Desktop: „WSL needs updating“ / „WSL 2 installation is incomplete“ | WSL fehlt oder ist alt | Schritt 2 wiederholen (`wsl --update`) |
| `docker` wird nicht erkannt | Docker Desktop nicht installiert oder PowerShell vor der Installation geöffnet | PowerShell neu öffnen; sonst Schritt 3 |
| „permission denied … docker_engine“ | Benutzer nicht in `docker-users` oder nicht neu angemeldet | Schritt 5, dann ab- und anmelden |
| „Cannot connect to the Docker daemon“ / „docker daemon is not running“ | Docker Desktop läuft nicht | Docker Desktop starten, warten bis „Engine running“ |

Alles andere: Fehlermeldung als Bildschirmfoto an Michl.
