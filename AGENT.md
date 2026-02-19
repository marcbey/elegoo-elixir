## 1. Ziel und Scope
- Re-Implementierung einer Browser-basierten Steueroberflaeche fuer das Elegoo Smart Robot Car V4.0.
- Fokus auf Chrome Desktop, lokale Steuerung ueber WLAN des Fahrzeugs.
- Firmware des Fahrzeugs wird nicht durch dieses Projekt geaendert.
- Zusaetzlich wird eine Terminal-CLI fuer die Steuerung und Diagnose bereitgestellt.

## 2. Nicht-Ziele
- Keine Firmware-Aenderung am AVR- oder ESP32-Teil des Fahrzeugs.
- Keine Cloud-Anbindung, kein Internetbetrieb, keine Remote-Steuerung ausserhalb des lokalen AP.
- Keine native Mobile-App (Web-App reicht fuer den ersten Scope).

## 3. Systemkontext
- Fahrzeug stellt WLAN AP bereit (typisch `ELEGOO-...`).
- Fahrzeug-Steuerung laeuft ueber TCP auf `192.168.4.1:100`.
- Kamera-Stream wird direkt per HTTP aus dem Browser geladen (`http://192.168.4.1:81/stream`).
- Die TCP-Verbindung zum Fahrzeug wird in Phoenix/Elixir ueber `:gen_tcp` umgesetzt (keine Node-Bridge).

## 4. Technologie-Stack
- Elixir
- Phoenix + LiveView
- Tailwind CSS
- optional Nerves (nur falls spaeter dedizierte Hardware fuer Bridge/Betrieb benoetigt wird)

## 5. Architektur (Soll)
- `CarTcpClient` (GenServer): Verwaltet `:gen_tcp` Verbindung, Reconnect, Framing (`{...}`), Heartbeat und Tx/Rx.
- `CarProtocol` (pure Module): Encodiert Commands und parst Antworten vom Fahrzeug.
- `Control` Context: Stellt fachliche API fuer Steuerung und Sensorabfragen bereit.
- LiveView UI: Joystick, Sensor-Dashboard, Verbindungsstatus, Not-Aus.
- CLI (`mix car ...`): Terminal-Interface fuer Steuer- und Sensorbefehle, nutzt denselben `Control` Context wie die Web-UI.
- Phoenix PubSub: Verteilt Telemetrie- und Verbindungsstatus in Echtzeit an die UI.

## 6. Kommunikationsprotokoll (Firmware-kompatibel)
- Nachrichten sind framebasiert mit `{...}` Abschluss.
- Steuerung und Sensoren basieren auf JSON-Kommandos `{"N":..., "D1":..., ...}`.
- Relevante Befehle aus der Original-Firmware:
  - `N=100`: Stop / Clear All Functions (Standby).
  - `N=3`: Car Control (ohne Zeitlimit, diskret: Richtung + Speed).
  - `N=4`: Motor Control Speed (nur vorwaerts, differenziell).
    - Firmware-Zuordnung ist wichtig: `D1` steuert Motor A (rechtes Rad), `D2` steuert Motor B (linkes Rad).
  - `N=1`: Motor Control (einzeln/beide Motoren mit Richtung).
    - Achtung: Bei Einzelradwahl (`D1=1` oder `D1=2`) wird der jeweils andere Motor im Firmware-Code auf `direction_void` gesetzt.
    - Deshalb ist `N=1` fuer kontinuierliche Joystick-Kurven ungeeignet (kann Ruckeln/konfliktierende Kommandos erzeugen).
  - `N=21`: Ultraschallstatus/-wert abfragen.
  - `N=22`: Liniensensor links/mitte/rechts abfragen.
  - `N=102`: Rocker-Befehle (diskrete Richtungen inkl. Stop).
  - `N=5`: Servo-Steuerung (`D1` = Servo-ID, `D2` = Winkelwert im Bereich `10..170`).
- Heartbeat muss unterstuetzt werden (`{Heartbeat}`), damit die Verbindung stabil bleibt.

## 7. Features der Steueroberflaeche
- Joystick-basierte Echtzeitsteuerung:
  - Winkeldefinition erfolgt im Uhrzeigersinn.
  - Joystick zeigt nach oben (`0°`): Fahrzeug faehrt vorwaerts.
  - Joystick zeigt nach rechts (`90°`): Fahrzeug dreht sich auf der Stelle nach rechts.
  - Joystick zeigt nach unten (`180°`): Fahrzeug faehrt rueckwaerts.
  - Joystick zeigt nach links (`270°`): Fahrzeug dreht sich auf der Stelle nach links.
  - Stufenlose Kurven werden primär ueber differenzielle Motorsteuerung umgesetzt.
  - Diskrete Richtungsbefehle werden als Fallback verwendet, wenn das Protokoll keine exakte stufenlose Abbildung erlaubt.
  - Je weiter der Joystick aus dem Zentrum gedrueckt wird, desto hoeher die Geschwindigkeit.
  - Lenkeinschlag ist auf `5°`-Schritte quantisiert (Bereich `-40°..40°`).
  - Geschwindigkeit ist auf `5%`-Schritte quantisiert.
  - Beim Loslassen springt der Joystick ins Zentrum und das Fahrzeug stoppt.
- Anzeige des Live-Video-Streams der Fahrzeugkamera.
- Anzeige der Ultraschall-Sensordaten.
- Anzeige der 3 Linien-Sensorwerte (links, mitte, rechts).
- Sichtbarer Verbindungsstatus (TCP ok/getrennt, Stream ok/fehlt).
- Not-Aus-Button, der sofort Stop (`N=100`) ausloest.
- Automatischer Verbindungsaufbau.
- Kamera-Servo-Steuerung:
  - Slider mit Mittelstellung (`90°` = geradeaus).
  - Schwenken nach links/rechts in `15°`-Schritten.
  - Begrenzung im UI auf `15°..165°` zur Vermeidung von Endanschlag-nahem Verhalten.
- Terminal-CLI:
  - Ausfuehrbar ueber `mix car ...` im Projektverzeichnis.
  - Unterstuetzt mindestens: `connect`, `stop`, `drive`, `turn`, `sensor`, `status`.
  - `turn` unterstuetzt stufenlose Kurvenfahrt ueber differenzielle Motorsteuerung (nicht nur diskrete Links/Rechts-Drehung).
  - Bei `turn` sind sowohl Lenkeinschlag (Kurvenstaerke) als auch Geschwindigkeit explizit steuerbar.
  - Gibt klare Textausgaben fuer Erfolg, Fehler und Verbindungszustand aus.

## 8. Safety und Laufzeitverhalten
- Bei Verbindungsabbruch oder Socket-Fehler wird automatisch Stop (`N=100`) ausgeloest (sofern Socket noch erreichbar) und UI auf "getrennt" gesetzt.
- Bei Inaktivitaet/Tab-Verlassen wird Stop gesendet.
- Steuerbefehle werden rate-limitiert (z. B. 20-30 Hz), um das Fahrzeug nicht mit Paketen zu ueberlasten.
- Sensorabfragen laufen getrennt von Steuerbefehlen und duplizieren keine Steuerframes.
- Waehrend aktiver Fahrt sollen Sensorabfragen gedrosselt/pausiert werden, damit Steuerbefehle priorisiert bleiben.

## 9. Konfiguration
- Konfigurierbar ueber `config/runtime.exs` oder ENV:
  - `CAR_HOST` (Default `192.168.4.1`)
  - `CAR_PORT` (Default `100`)
  - `CAR_STREAM_URL` (Default `http://192.168.4.1:81/stream`)
  - `CONTROL_TICK_MS` (z. B. 33-50 ms)
  - `SENSOR_POLL_MS` (z. B. 150-300 ms)
  - `CLI_TIMEOUT_MS` (Default fuer TCP/Command-Timeout in der CLI)

## 10. Spezifikation und Referenzen
- Alle verfuegbaren Spezifikationen und Originalquellen liegen unter `docs/`.
- Relevante Referenzen:
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/SmartRobotCarV4.0_V0_20210104/ApplicationFunctionSet_xxx0.cpp`
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/ESP32-WROVER-Camera/ESP32_CameraServer_AP_20210107/ESP32_CameraServer_AP_20210107.ino`
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/ESP32-WROVER-Camera/ESP32_CameraServer_AP_20210107/app_httpd.cpp`

## 11. Abnahmekriterien (MVP)
- Verbindung zum Fahrzeug soll automatisch aufgebaut und stabil gehalten werden.
- Joystick steuert vorwaerts/rueckwaerts/drehen sicher und reproduzierbar.
- Kurvenfahrt reagiert stufenlos im verfuegbaren Protokollrahmen.
- Bei Loslassen des Joysticks stoppt das Fahrzeug sofort.
- Ultraschall- und Linien-Sensorwerte aktualisieren sich live.
- Video-Stream wird in der UI angezeigt.
- CLI ist ueber Terminal nutzbar (`mix car ...`) und kann mindestens verbinden, stoppen, fahren und Sensordaten lesen.
- CLI-`turn` ermoeglicht stufenlose Kurvenfahrt mit kontrollierbarer Geschwindigkeit und reproduzierbarem Lenkeinschlag.
- Fehlerfaelle (Disconnect, fehlender Stream, Timeout) sind im UI sichtbar und fuehren zu sicherem Verhalten.

## 12. Verifizierte Implementierungsdetails (seit initialer Umsetzung)
- Diese Punkte sind aus der realen Implementierung/Firmware-Analyse abgeleitet und sollten bei einer Neu-Implementierung unveraendert beruecksichtigt werden.

- Steuerungsstrategie (wichtig):
  - Vorwaerts + Kurve: primaer ueber `N=4` (differenzielle Vorwaerts-Geschwindigkeit links/rechts).
  - Rueckwaerts: nicht ueber `N=4` (da nur vorwaerts), sondern ueber `N=3` mit Richtung `backward`.
  - Drehen auf der Stelle: ueber `N=3` mit Richtung `left`/`right`.
  - Stop: immer `N=100`.
  - Kamera-Servo: ueber `N=5`, fuer den Kamera-Schwenkservo `D1=1`.
    - Winkel wird als `D2=angle` gesendet (nicht `*10`).
    - Firmware rechnet intern `Position_angle = D2 / 10` und schreibt `10 * Position_angle`.
    - UI quantisiert auf `15°`-Raster, mit Zentrum bei `90°`.

- Joystick-Mapping (praxisbewaehrt):
  - Eingang: normalisierte Achsen `x,y` in `[-1.0,1.0]`.
  - Deadzone nahe Zentrum (ca. `0.04`) anwenden.
  - `x` zuerst auf Lenkwinkel quantisieren (`5°` Raster), dann in Mischanteil umrechnen.
  - Virtuelle Radwerte:
    - `left = y + x_mix`
    - `right = y - x_mix`
    - auf Maximalbetrag normieren, in `[-255,255]` mappen, danach auf `5%`-Stufen quantisieren.
  - Kommandowahl aus Radwerten:
    - beide >= 0: `N=4` (vorwaerts differenziell),
    - beide <= 0: `N=3 backward` (bei grossem Lenkwinkel optional `left/right`),
    - gegenlaeufige Vorzeichen: `N=3 left/right`.

- Entkopplung/Entlastung:
  - Nicht jedes Joystick-Event sofort senden; deduplizieren ueber einen stabilen `command_key`.
  - Sensorpoll waehrend aktiver Fahrt reduzieren/pausieren.
  - Kurze Sensor-Timeouts (z. B. `250ms`) vermeiden Blockierung der Steuerung.

- UI/LiveView-Stabilitaet (gegen "Springen"):
  - Joystick-Container mit `phx-update="ignore"` versehen, damit LiveView-Patches den Knob-Transform nicht zuruecksetzen.
  - Fehler nicht als ein-/ausblendende Inline-Message im normalen Layout rendern.
  - Stattdessen nur ein Fehler-Icon direkt neben dem Verbindungsbadge verwenden.
  - Fuer Badge + Icon festen Platz reservieren (feste/minimale Breite, Icon-Platz immer vorhanden), um Layout-Shift bei Statuswechsel `Verbunden/Getrennt` zu vermeiden.

- Browser/Hook-Verhalten:
  - Pointer-Ereignisse: `pointerdown`, `pointermove`, `pointerup`, `pointercancel`, `lostpointercapture`.
  - Bei `blur`/`visibilitychange` immer sofort `joystick_release` senden.
  - `setPointerCapture`/`releasePointerCapture` defensiv in `try/catch` behandeln.
  - Beim Release muss sofort `Stop` gesendet und UI intern auf Zentrum zurueckgesetzt werden.
  - Not-Aus-Button-Feedback soll clientseitig (Hook-basiert) sofort beim Klick sichtbar sein, unabhaengig vom Server-Roundtrip.
    - Aktueller Standard: Tailwind-UI-nahes rotes Button-Pattern (Focus-Ring, Hover/Active States), Beschriftung "Not Aus", plus kurzer CSS-Schatten-Effekt beim Klick.

- Netz/Diagnose:
  - Meldung "keine TCP-Verbindung" bedeutet meist: Host hat keine Route zu `192.168.4.1:100` (nicht zwingend UI-Fehler).
  - Schneller Check: `nc -vz 192.168.4.1 100`.

## 13. Pflege der AGENT.md (verbindlich)
- Alle relevanten Erkenntnisse aus jeder Session muessen in `AGENT.md` nachgefuehrt werden, sobald sie als valide Verbesserung/Fix bestaetigt sind.
- Dazu zaehlen mindestens:
  - geaenderte Steuerlogik und Protokoll-Mappings,
  - UI/UX-Stabilitaetsverbesserungen (z. B. gegen Layout-Shift),
  - Performance-/Latenzoptimierungen,
  - bekannte Fehlerbilder und deren Diagnoseweg,
  - neue Betriebs- und Safety-Regeln.
- Die Nachfuehrung soll konkret und reproduzierbar sein (keine vagen Formulierungen, immer mit klaren Regeln/Schwellenwerten falls vorhanden).
- Ziel: Eine Neu-Implementierung soll allein anhand von `AGENT.md` ohne Session-Kontext moeglich sein.

    
    
