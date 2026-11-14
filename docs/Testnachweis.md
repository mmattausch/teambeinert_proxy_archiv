# Testnachweis: Proxy-Skript v5 und Archivskript gegen die bisherigen Skripte

Stand: 14.11.2026 · Strang PX · Maßnahmen M-01 und M-39

Dieses Dokument zeigt, welche Dateien mit welchen Skripten und welchen Parametern getestet wurden und wie die Gleichheit der Ergebnisse nachgewiesen ist.

## 1. Kurzfassung

| Prüfung | Proxy (v4 → v5) | Archiv (altes → neues `archiv_h264.sh`) |
|---|---|---|
| Echte Aufnahmen, Testkorpus auf ELSA | 63 von 63 bitgleich, 63 von 63 gleich groß, alle bestehen die Prüfung | 64 von 64 bitgleich, 64 von 64 gleich groß, alle bestehen die Prüfung |
| ffmpeg-Argumente, 39 erzeugte Testdateien | 32 gleich, 7 erklärte Fehler von v4, 0 ungleich | 32 gleich, 7 erklärte Fehler des alten Skripts, 0 ungleich |
| Bild und Ton, 39 erzeugte Testdateien (VM, gleiches Image) | 27 bitgleich, 12 erklärt, 0 ungleich | 28 bitgleich, 11 erklärt, 0 ungleich |
| Ablauftests (Abbruch, Sperre, Fortsetzen, Namen …) | 49 von 49 bestanden | 42 von 42 bestanden |

Die ATEM-Mini-ISO-Datei kam erst nach dem Proxy-Lauf in den Testordner; sie ist im Archiv-Lauf enthalten, im Proxy-Lauf nicht.

## 2. Skripte und Parameter

| | Bisher | Neu |
|---|---|---|
| Proxy | `/mnt/Mirror_2x8TB/Proxy_Output/proxy_conv_docker_v4.sh`, sha256 `36e29763…ad4132` (Ist-Stand 09.01.2026) | `proxy_v5.sh` mit `lib/proxy_profil.sh`, Kennung `proxy_h264_540_v1` |
| Archiv | `/mnt/Mirror_2x8TB/Proxy_Output/archiv_h264.sh`, sha256 `0426c8e6…97cdf58` (Ist-Stand 09.01.2026) | `archiv_h264.sh` mit `lib/archiv_profil.sh`, Kennung `archiv_h264_crf18_v1` |
| ffmpeg | `linuxserver/ffmpeg` (Tag `latest`) | `linuxserver/ffmpeg@sha256:784db915…c697`; auf ELSA ist `latest` genau dieses Image (ffmpeg 8.0). Beide Seiten nutzten im Test dasselbe Image. |

**ffmpeg-Argumente Proxy** (beide Fassungen, Reihenfolge wie im Aufruf):

```
-i <Quelle> -vf scale=-1:540 -pix_fmt yuv420p -timecode <TC>
[<Ton-Zuordnung>]
-c:v libx264 -c:a aac -profile:v main -level 2.1 -preset veryfast -tune fastdecode
-crf 21 -threads 4 -x264opts keyint=75 <Ziel>
```

**ffmpeg-Argumente Archiv** (beide Fassungen):

```
-i <Quelle> -pix_fmt yuv420p10le -timecode <TC>
[<Ton-Zuordnung>]
-c:v libx264 -c:a aac -preset veryfast -tune fastdecode -crf 18 -threads 4
-x264opts keyint=75 <Ziel>
```

**Timecode** (beide Skripte, alt und neu gleich): erster Treffer `timecode : HH:MM:SS:FF` in der Ausgabe von `ffmpeg -i <Quelle>`, sonst `00:00:00:00`.

**Ton-Zuordnung** (beide Skripte, alt und neu gleich), je Tonspur des Originals:
- Spur mit 1, 2, 4, 6 oder 8 Kanälen: `-map 0:v -map 0:a` (alle Spuren 1:1, AAC).
- andere Kanalzahl: je Kanal `[0:a]pan=mono|c0=cN[aN]` als eigene Monospur, dazu `-map 0:0 -map 0:1`.
- kein Ton: keine `-map`-Angabe, ffmpeg wählt selbst.

**Nur in der neuen Fassung zusätzlich** (Änderungsliste M11; ändern die Datei nicht): `-nostdin`, `-hide_banner -loglevel error`, `-f mov` vor dem Ziel, Ziel zuerst als `<Ziel>.teil`, Container mit Namen, Quelle nur lesend eingebunden statt `-v /mnt:/mnt`.

## 3. Wie die Gleichheit bewiesen wurde

**a) Gleiche Argumente** (`tests/v4_vergleich.sh`, `tests/archiv_vergleich.sh`): Das alte Skript läuft unverändert bis auf die Pfadvariablen `searchpath` und `basedir`. Ein Ersatz für `docker` lässt ffprobe und den Timecode-Aufruf wirklich laufen, schreibt den eigentlichen ffmpeg-Aufruf aber nur mit. Die neue Fassung gibt ihren Aufruf mit `--befehl` aus. Verglichen wird die Liste der Argumente nach dem Image, Element für Element; die zusätzlichen Angaben aus Abschnitt 2 werden vorher entfernt.

**b) Gleiche Dateien** (`tests/korpus_vergleich.sh`, auf ELSA):
1. Das echte alte Skript rechnet jede Datei des Testordners. In einer Testkopie sind nur die Pfadvariablen (`basedir`, beim Proxy zusätzlich `proxydest` und `proxydestfile`) auf ein Testverzeichnis gestellt; Prüfsumme und Image werden vorher kontrolliert.
2. Die neue Fassung rechnet dieselbe Datei mit dem Aufruf aus `--befehl`, Ziel ebenfalls im Testverzeichnis, Quelle nur lesend.
3. Beide Ergebnisse werden mit `ffmpeg -i <Datei> -map 0:v -map 0:a? -f framemd5 -` vollständig dekodiert; das ergibt je Bild und je Tonpaket eine MD5-Prüfsumme. Die beiden Listen müssen identisch sein („bitgleich“ in Bild und Ton).
4. Zusätzlich: Dateigröße beider Ausgaben, und die Prüfung der neuen Fassung (Laufzeit, Videospur, Höhe bzw. Auflösung, Ton) auf den neuen Ausgaben.

Der Testordner selbst wurde nur gelesen. Die Proxys der Schnittplätze in `Proxies/` blieben unberührt.

**c) Ablauftests** (`tests/lauf_tests.sh`, `tests/archiv_tests.sh`) mit den 45 erzeugten Testdateien: Verhalten außerhalb von ffmpeg (Abbruch, Sperre, Fortsetzen, Ausschlüsse, Protokoll), siehe Abschnitt 5.

## 4. Testkorpus `Aufnahmen/2025-03-04_PROXY` (echte Aufnahmen)

Proxy-Lauf: 14.11.2026, 00:04–00:30 (Rechenzeit v4 590 s, v5 565 s). Archiv-Lauf: 14.11.2026, 17:28–20:30 (Rechenzeit alt 3.964 s, neu 3.978 s).

| Nr. | Datei | Video | Ton im Original | Laufzeit | Ton-Zuordnung | Proxy v4 → v5 | Archiv alt → neu |
|---|---|---|---|---|---|---|---|
| 1 | `ATEM_Mini_ISO/VEGA_Live-SWINGX_XCOMs CAM 4 02.mp4` | h264, 1920×1080, 50 fps, yuv420p, progressiv | 2 Kanäle | 349,26 s | `-map 0:v -map 0:a` | nicht im Lauf | bitgleich, Größe gleich, Prüfung ok |
| 2 | `Avatar/Avatar_2-7K_120p_h265.MP4` | hevc, 2688×1512, 119,88 fps, yuv420p, progressiv | kein Ton | 5,69 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 3 | `Avatar/Avatar_4K_60p_h264.MP4` | h264, 3840×2160, 59,94 fps, yuv420p, progressiv | kein Ton | 3,15 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 4 | `FS7/FS7_MPEG-HD_422.MXF` | mpeg2video, 1920×1080, 29,97 fps, yuv422p, Zeilensprung | 8 × 1 Kanal | 5,34 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 5 | `FS7/FS7_ProRes_422.MOV` | prores, 1920×1080, 29,97 fps, yuv422p10le, progressiv | 4 × 1 Kanal | 6,51 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 6 | `FS7/FS7_ProRes_HQ-422.MOV` | prores, 1920×1080, 29,97 fps, yuv422p10le, progressiv | 4 × 1 Kanal | 7,17 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 7 | `FS7/FS7_XAVC-I.MXF` | h264, 3840×2160, 59,94 fps, yuv422p10le, progressiv | 8 × 1 Kanal | 5,51 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 8 | `FS7/FS7_XAVC-L.MXF` | h264, 3840×2160, 59,94 fps, yuv420p, progressiv | 4 × 1 Kanal | 6,67 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 9 | `FX3/C4192.MP4` | h264, 3840×2160, 29,97 fps, yuvj420p, progressiv | 4 × 1 Kanal | 154,65 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 10 | `FX3/C4212-4ch.MP4` | h264, 3840×2160, 29,97 fps, yuvj420p, progressiv | 4 × 1 Kanal | 8,01 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 11 | `FX3/FX3_XAVC_HS_4K_100M_420_10bit_C4056.MP4` | hevc, 3840×2160, 23,976 fps, yuv420p10le, progressiv | 2 Kanäle | 23,52 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 12 | `FX3/FX3_XAVC_HS_4K_100M_420_8bit_C4060.MP4` | h264, 3840×2160, 29,97 fps, yuvj420p, progressiv | 2 Kanäle | 25,53 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 13 | `FX3/FX3_XAVC_HS_4K_100M_422_10bit_C4055.MP4` | hevc, 3840×2160, 23,976 fps, yuv422p10le, progressiv | 2 Kanäle | 13,51 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 14 | `FX3/FX3_XAVC_HS_4K_50M_420_10bit_C4058.MP4` | hevc, 3840×2160, 23,976 fps, yuv422p10le, progressiv | 2 Kanäle | 18,02 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 15 | `FX3/FX3_XAVC_HS_4K_50M_420_10bit_C4058_1.mov` | h264, 960×540, 23,976 fps, yuv420p, progressiv | 2 Kanäle | 18,02 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 16 | `FX3/FX3_XAVC_HS_4K_50M_422_10bit_C4057.MP4` | hevc, 3840×2160, 23,976 fps, yuv422p10le, progressiv | 2 Kanäle | 18,02 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 17 | `FX3/FX3_XAVC_S-I_4K_600M_422_10bit_C4072.MP4` | h264, 3840×2160, 59,94 fps, yuv422p10le, progressiv | 2 Kanäle | 29,53 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 18 | `FX3/FX3_XAVC_S_4K_140M_422_10bit_C4059.MP4` | h264, 3840×2160, 29,97 fps, yuv422p10le, progressiv | 2 Kanäle | 22,52 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 19 | `GH5/GH5_AVCHD-FHD_17M_50i.MTS` | h264, 1920×1080, 50 fps, yuv420p, Zeilensprung | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 20 | `GH5/GH5_AVCHD-FHD_28M_50p.MTS` | h264, 1920×1080, 50 fps, yuv420p, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 21 | `GH5/GH5_MOV_4K_10bit_150M_25p.MOV` | h264, 3840×2160, 25 fps, yuv422p10le, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 22 | `GH5/GH5_MOV_4K_8bit_100M_25p.MOV` | h264, 3840×2160, 25 fps, yuv420p, progressiv | 2 Kanäle | 12,00 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 23 | `GH5/GH5_MOV_4K_8bit_150M_50p.MOV` | h264, 3840×2160, 50 fps, yuv420p, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 24 | `GH5/GH5_MOV_4K_All-i_400M_25p.MOV` | h264, 3840×2160, 25 fps, yuv422p10le, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 25 | `GH5/GH5_MOV_FHD_10bit_100M_25p.MOV` | h264, 1920×1080, 25 fps, yuv422p10le, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 26 | `GH5/GH5_MOV_FHD_10bit_100M_50p.MOV` | h264, 1920×1080, 50 fps, yuv422p10le, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 27 | `GH5/GH5_MOV_FHD_8bit_100M_25p.MOV` | h264, 1920×1080, 25 fps, yuv420p, progressiv | 2 Kanäle | 11,52 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 28 | `GH5/GH5_MOV_FHD_8bit_100M_50p.MOV` | h264, 1920×1080, 50 fps, yuv420p, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 29 | `GH5/GH5_MOV_FHD_All-i_200M_25p.MOV` | h264, 1920×1080, 25 fps, yuv422p10le, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 30 | `GH5/GH5_MOV_FHD_All-i_200M_50p.MOV` | h264, 1920×1080, 50 fps, yuv422p10le, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 31 | `GH5/GH5_MP4-LPCM_4K_8bit_150M_25p.MP4` | h264, 3840×2160, 50 fps, yuv420p, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 32 | `GH5/GH5_MP4-LPCM_FHD_8bit_100M_25p.MP4` | h264, 1920×1080, 25 fps, yuv420p, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 33 | `GH5/GH5_MP4-LPCM_FHD_All-i_200M_25p.MP4` | h264, 1920×1080, 25 fps, yuv422p10le, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 34 | `GH5/GH5_MP4-LPCM_FHD_All-i_200M_50p.MP4` | h264, 1920×1080, 50 fps, yuv422p10le, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 35 | `GH5/GH5_MP4-hevc_4K_72M_25p.MP4` | hevc, 3840×2160, 25 fps, yuv420p10le, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 36 | `GH5/GH5_MP4_4K_100M_25p.MP4` | h264, 3840×2160, 25 fps, yuv420p, progressiv | 2 Kanäle | 10,56 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 37 | `GH5/GH5_MP4_FHD_20M_25p.MP4` | h264, 1920×1080, 25 fps, yuv420p, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 38 | `GH5/GH5_MP4_FHD_28M_50p.MP4` | h264, 1920×1080, 50 fps, yuv420p, progressiv | 2 Kanäle | 11,04 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 39 | `GoPro/GoPro-Timelapse_h265-main_5312x2988px_GX012026.MP4` | hevc, 5312×2988, 25 fps, yuvj420p, progressiv | kein Ton | 12,48 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 40 | `Hyperdeck/HyperDeck_ProRes_422_LT_pcm24sle_16ch_Capture0007.mov` | prores, 3840×2160, 25 fps, yuv422p10le, progressiv | 16 Kanäle | 7,76 s | `pan=mono` je Kanal + `-map 0:0 -map 0:1` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 41 | `Hyperdeck/HyperDeck_h265_4K_pcm24sle_2ch_HyperDeck_0007.mp4` | hevc, 3840×2160, 25 fps, yuv422p10le, progressiv | 2 Kanäle | 3,36 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 42 | `Mavic3/DJI_Mavic3_4K_ProRes-LT_422.MOV` | prores, 3840×2160, 50 fps, yuv422p10le, progressiv | kein Ton | 6,54 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 43 | `Mavic3/DJI_Mavic3_4K_h264-mov.MOV` | h264, 3840×2160, 50 fps, yuv420p10le, progressiv | kein Ton | 7,10 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 44 | `Mavic3/DJI_Mavic3_4K_h264-mp4.MP4` | h264, 3840×2160, 50 fps, yuv420p10le, progressiv | kein Ton | 5,50 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 45 | `Mavic3/DJI_Mavic3_4K_h265-mov.MOV` | hevc, 3840×2160, 50 fps, yuv420p10le, progressiv | kein Ton | 9,10 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 46 | `Mavic3/DJI_Mavic3_4K_h265-mp4.MP4` | hevc, 3840×2160, 50 fps, yuv420p10le, progressiv | kein Ton | 5,54 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 47 | `Mavic3/DJI_Mavic3_5K_h265-mp4.MP4` | hevc, 5120×2700, 50 fps, yuv420p10le, progressiv | kein Ton | 5,88 s | kein Ton: ohne `-map` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 48 | `Ordner mit Leerzeichen/leerzeichen drin.MOV` | dnxhd, 3840×2160, 60 fps, yuv422p, progressiv | 4 Kanäle | 6,62 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 49 | `Ordner mit Leerzeichen/sonderzeichen drin _Ö_â_Kopie.MOV` | dnxhd, 3840×2160, 60 fps, yuv422p, progressiv | 4 Kanäle | 6,62 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 50 | `Sumo/Sumo_1080i_5994_ProrRes422.MOV` | prores, 1920×1080, 29,97 fps, yuv422p10le, Zeilensprung | 4 Kanäle | 7,91 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 51 | `Sumo/Sumo_1080i_5994_ProrResHQ.MOV` | prores, 1920×1080, 29,97 fps, yuv422p10le, Zeilensprung | 4 Kanäle | 10,14 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 52 | `Sumo/Sumo_1080i_5994_ProrResLT.MOV` | prores, 1920×1080, 29,97 fps, yuv422p10le, Zeilensprung | 4 Kanäle | 10,91 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 53 | `Sumo/Sumo_1080p_2997_ProrRes422.MOV` | prores, 1920×1080, 29,97 fps, yuv422p10le, progressiv | 4 Kanäle | 9,44 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 54 | `Sumo/Sumo_4KUHDp_50_ProRes422.MOV` | prores, 3840×2160, 50 fps, yuv422p10le, progressiv | 4 Kanäle | 10,62 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 55 | `Sumo/Sumo_4KUHDp_5994_ProRes422.MOV` | prores, 3840×2160, 59,94 fps, yuv422p10le, progressiv | 4 Kanäle | 7,42 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 56 | `URSA/URSA_DNXHD_220x.mov` | dnxhd, 1920×1080, 30 fps, yuv422p10le, progressiv | 2 Kanäle | 3,50 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 57 | `URSA/URSA_ProRes_422.mov` | prores, 3840×2160, 30 fps, yuv422p10le, progressiv | 2 Kanäle | 2,37 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 58 | `URSA/URSA_ProRes_444.mov` | prores, 3840×2160, 30 fps, yuv444p12le, progressiv | 2 Kanäle | 2,53 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 59 | `URSA/URSA_ProRes_XQ.mov` | prores, 3840×2160, 30 fps, yuv444p12le, progressiv | 2 Kanäle | 2,23 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 60 | `URSA/URSA_ProRes_XQ_LT.mov` | prores, 3840×2160, 30 fps, yuv422p10le, progressiv | 2 Kanäle | 3,43 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 61 | `a7iv/a7iv_XAVC_HS_4K_422_10bit_100M_C2039.MP4` | hevc, 3840×2160, 59,94 fps, yuv422p10le, progressiv | 2 Kanäle | 4,50 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 62 | `a7iv/a7iv_h264_422_4K_C1759.MP4` | h264, 3840×2160, 50 fps, yuv422p10le, progressiv | 2 Kanäle | 11,52 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 63 | `shogun/Shogun_DNxHR_HQ.MOV` | dnxhd, 3840×2160, 60 fps, yuv422p, progressiv | 4 Kanäle | 6,62 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |
| 64 | `shogun/Shogun_ProRes_422.MOV` | prores, 3840×2160, 60 fps, yuv422p10le, progressiv | 4 Kanäle | 5,95 s | `-map 0:v -map 0:a` | bitgleich, Größe gleich, Prüfung ok | bitgleich, Größe gleich, Prüfung ok |

Ton-Angaben aus der ffprobe-Messung vom 12.11.2026 (`phase0/korpus_ffprobe.sh`), ATEM Mini ISO aus der Abfrage vom 14.11.2026.

## 5. Erzeugte Testdateien (`tests/erzeuge_testdateien.sh`)

Kurze Dateien (2 s, 640×360, H.264), erzeugt mit demselben ffmpeg. Sie decken ab, was der Testkorpus nicht hat. Gerechnet in der Colima-VM auf dem Mac; für den Vergleich von Bild und Ton mit identischem Image auf beiden Seiten.

| Gruppe | Dateien | Zweck | Proxy v5 | Archiv neu | Vergleich mit dem alten Skript |
|---|---|---|---|---|---|
| Namen | `normal`, `mit Leerzeichen`, `Umlaute_äöüß_ÄÖÜ`, `Semikolon; und & und [Klammern]`, `Doppel:punkt`, `-beginnt_mit_minus`, 18-fach langer Name, `GROSS_ENDUNG.MP4`, `Backslash\im_Namen` | schwierige Zeichen im Namen | ok | ok | gleich |
| Bösartige Namen | `clip$(cd;touch proxy_v5_pwned)`, ``clip`cd;touch proxy_v5_pwned2` `` | Befehl im Dateinamen (Schwachstelle a) | ok, nichts ausgeführt | ok, nichts ausgeführt | erklärt: altes Skript führt den Befehl aus und zerlegt den Namen |
| Anführungszeichen, Zeilenumbruch | `Anführung "doppelt" und 'einfach'`, `Zeilen⏎umbruch` | `eval`-Fehler | ok | ok | erklärt: altes Skript zerlegt den Namen |
| Ton | ohne, 1, 4, 6, 8 Kanäle; 4 × Mono; 2 × Stereo | normale Tonaufbauten | ok | ok | gleich |
| Ton 3/5/7 | 3, 5, 7 Kanäle (Ton an Spur 1) | Mono-Aufteilung, Originalspur zusätzlich | ok (Kanäle doppelt, Proxy brauchbar) | `Fehler` (Kanalsumme verdoppelt) | gleich |
| Ton > 8 | 16 Kanäle; 16 + 2; 2 × 16 (Ton an Spur 1) | AAC kann höchstens 8 Kanäle in einer Spur | `Fehler` | `Fehler` | erklärt: ffmpeg scheitert in beiden; altes Skript hinterlässt 0-Byte-Datei |
| Ton 2 + 16 | 2 + 16 Kanäle | fehlendes Leerzeichen im alten Skript (`0:a-map`) | `Fehler` | `Fehler` | erklärt: scheitert in beiden |
| Kein Video | `nur_ton_kein_video.mov` | Videoendung ohne Bild | `kein_video` | `kein_video` | erklärt: altes Skript startet ffmpeg, das scheitert ohne Meldung; neues meldet `kein_video` |
| Timecode | ohne, 25p, 29,97 mit Drop-Frame | Timecode-Übernahme | ok | ok | gleich |
| Bild | zwei Videospuren, 1080×1920 hoch, 10 Bit 4:2:2, MXF mit 8 × Mono, MTS mit AC3 | Formate | ok | ok | gleich |
| Ungerade Breite | 1918×1080 | `scale=-1:540` ergibt 959 px | `Fehler` (x264 verweigert) | ok (keine Skalierung) | Proxy: erklärt, scheitert in beiden; Archiv: gleich |
| Defekt | auf die Hälfte gekürzte MP4, Textdatei mit `.mp4` | nicht lesbare Quelle | `Fehler` | `Fehler` | erklärt: altes Skript startet ffmpeg trotzdem |
| Auswahl | `.versteckt.mp4`, `Proxies/alter_proxy.mov`, `00_to_Backup/…`, `01_zum_Band/…`, `.mkv` | Ausschlüsse | übersprungen | übersprungen | – |
| Auswahl | `VID_20260102_120000_00_001.mp4`, `Tag_100_Bühne.mov` | `00_` im Dateinamen (Befund 9) | ok | ok (altes Skript übersprang sie) | – |
| Auswahl | `im_wurzelordner.mp4` | Datei direkt unter `Aufnahmen` | ok, zentraler Pfad richtig | – | – |

Die Zahlen der Ablauftests (49 bzw. 42 Prüfungen) und die einzelnen Prüfungen stehen in `tests/lauf_tests.sh` und `tests/archiv_tests.sh`.

## 6. Grenzen des Nachweises

- `framemd5` vergleicht den dekodierten Inhalt (Bild und Ton). Zusätzlich sind alle Ausgaben gleich groß. Ein Byte-für-Byte-Vergleich der ganzen Dateien wurde nicht gemacht.
- Die erzeugten Testdateien liefen auf dem Mac in der Colima-VM mit der arm64-Fassung desselben Images; die echten Aufnahmen auf ELSA mit der amd64-Fassung (wie im Betrieb).
- Am Schnittrechner (Docker Desktop unter Windows) ist noch nichts getestet.
- Die DaVinci-Sichtprüfung steht aus; nach diesen Ergebnissen sind die Proxys und Archiv-Fassungen inhaltlich dieselben wie bisher.
