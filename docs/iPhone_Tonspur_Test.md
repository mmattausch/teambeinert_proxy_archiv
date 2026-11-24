# iPhone-Aufnahmen ohne Proxy: bitte in DaVinci testen

Stand: 24.11.2026 · für Thomas · von Michl

## Worum es geht

Für vier iPhone-Aufnahmen entsteht seit Dezember 2025 kein Proxy:

```
Y:\2025_12_05_Alex_fuer_Malte\IMG_4931.MOV
Y:\2025_12_05_Alex_fuer_Malte\IMG_4932.MOV
Y:\2025_12_05_Alex_fuer_Malte\IMG_4933.MOV
Y:\2025_12_05_Alex_fuer_Malte\IMG_4934.MOV
```

Die Dateien haben eine zusätzliche Tonspur (Spur Nr. 2), die ffmpeg nicht kennt (Meldung: „no decoder found for: none“). Vermutlich ist das der räumliche Ton neuerer iPhones. Das Proxy-Skript nimmt alle Tonspuren mit, scheitert an dieser einen und erzeugt dann gar nichts.

Wir könnten das Skript so ändern, dass es diese Spur weglässt. Vorher wollen wir wissen, ob die so erzeugten Proxys in DaVinci sauber funktionieren und ob die fehlende Spur im Schnitt gebraucht wird.

## Vorbereitung

PowerShell öffnen (normale Rechte genügen). Einen Testordner anlegen und die Originale hineinkopieren:

```powershell
mkdir D:\iPhonetest
```

```powershell
copy Y:\2025_12_05_Alex_fuer_Malte\IMG_493*.MOV D:\iPhonetest\
```

```powershell
cd D:\iPhonetest
```

Welche ffmpeg-Version ist installiert? (erste Zeile bitte ins Feedback):

```powershell
ffmpeg -version
```

## Schritt 1: Spuren der Originale ansehen

```powershell
ffprobe -v error -show_entries stream=index,codec_type,codec_name,codec_tag_string,channels,width,height,pix_fmt,color_transfer:stream_tags=handler_name -of compact IMG_4931.MOV
```

Die Ausgabe bitte mitschicken. Man sieht darin jede Spur mit Nummer (`index=…`), Art (Video, Ton, Daten) und Codec.

## Schritt 2: Proxys in drei Varianten bauen

Alle drei Varianten nutzen dieselben Einstellungen wie unser Proxy-Skript (540p, H.264). Sie unterscheiden sich nur darin, welche Tonspuren mitkommen. Für jede Variante entsteht ein eigener Ordner, damit man sie in DaVinci getrennt per „Link Proxy“ verknüpfen kann.

```powershell
mkdir Proxies_A, Proxies_B, Proxies_C
```

**Variante A – wie heute (alle Spuren).** Erwartet: Fehler, es entsteht keine Datei. Nur zur Bestätigung, eine Datei genügt:

```powershell
ffmpeg -i IMG_4931.MOV -vf scale=-1:540 -pix_fmt yuv420p -timecode 00:00:00:00 -map 0:v -map 0:a -c:v libx264 -c:a aac -profile:v main -level 2.1 -preset veryfast -tune fastdecode -crf 21 -threads 4 -x264opts keyint=75 Proxies_A\IMG_4931.mov
```

**Variante B – nur die erste Tonspur.**

```powershell
foreach ($n in 4931,4932,4933,4934) { ffmpeg -y -i "IMG_$n.MOV" -vf scale=-1:540 -pix_fmt yuv420p -timecode 00:00:00:00 -map 0:v -map 0:a:0 -c:v libx264 -c:a aac -profile:v main -level 2.1 -preset veryfast -tune fastdecode -crf 21 -threads 4 -x264opts keyint=75 "Proxies_B\IMG_$n.mov" }
```

**Variante C – alle Tonspuren außer Spur Nr. 2.** Falls Schritt 1 zeigt, dass die unbekannte Spur eine andere Nummer hat, `-map -0:2` entsprechend anpassen.

```powershell
foreach ($n in 4931,4932,4933,4934) { ffmpeg -y -i "IMG_$n.MOV" -vf scale=-1:540 -pix_fmt yuv420p -timecode 00:00:00:00 -map 0:v -map 0:a -map -0:2 -c:v libx264 -c:a aac -profile:v main -level 2.1 -preset veryfast -tune fastdecode -crf 21 -threads 4 -x264opts keyint=75 "Proxies_C\IMG_$n.mov" }
```

Wenn B und C dieselbe Anzahl Tonspuren haben, sind sie praktisch gleich; dann genügt eine der beiden.

## Schritt 3: In DaVinci ansehen

1. Die vier Originale aus `D:\iPhonetest` in ein Testprojekt holen.
2. Per „Link Proxy Media“ einmal `Proxies_B`, einmal `Proxies_C` verknüpfen.
3. Ansehen und anhören, im Original und mit Proxy.

## Feedback an Michl

Bitte kurz zu jedem Punkt:

1. Erste Zeile von `ffmpeg -version` und die Ausgabe von Schritt 1.
2. Variante A: Fehler wie erwartet?
3. Wie viele Tonspuren zeigt DaVinci beim **Original**? Spielt DaVinci alle ab, auch die zusätzliche?
4. Verknüpft DaVinci die Proxys aus B bzw. C problemlos? Laufen Bild und Ton synchron?
5. Fehlt im Proxy etwas, das im Schnitt gebraucht wird (z. B. der räumliche Ton)?
6. Sehen die Farben im Proxy richtig aus? (iPhones filmen oft in HDR; der Proxy ist 8 Bit SDR und kann blasser oder kräftiger wirken. Für einen Schnittproxy ist das vielleicht egal, bitte trotzdem einschätzen.)
7. Welche Variante würdest du nehmen?

Danach kann `D:\iPhonetest` gelöscht werden.
