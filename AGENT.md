## 1. Ziel und Scope
- Re-Implementierung einer Browser-Steueroberflaeche fuer das Elegoo Smart Robot Car V4.0.
- Fokus: Chrome Desktop, lokale Steuerung ueber Fahrzeug-WLAN.
- Firmware wird nicht geaendert.
- Zusaetzlich wird eine Terminal-CLI bereitgestellt.

## 2. Nicht-Ziele
- Keine AVR-/ESP32-Firmware-Aenderungen.
- Keine Cloud-/Internet-Remote-Steuerung.
- Keine native Mobile-App im MVP.

## 3. Systemkontext
- Fahrzeug als WLAN-AP (typisch `ELEGOO-...`).
- Steuerkanal: TCP `192.168.4.1:100`.
- Videokanal: HTTP-Stream `http://192.168.4.1:81/stream`.
- TCP-Handling erfolgt in Phoenix/Elixir via `:gen_tcp`.

## 4. Technologie-Stack
- Elixir
- Phoenix + LiveView
- Tailwind CSS

## 5. Zielarchitektur
- `CarTcpClient` (GenServer): Connection-Lifecycle, Reconnect, Framing (`{...}`), Heartbeat, Tx/Rx.
- `CarProtocol`: Protokoll-Encoding/Decoding (reine Logik).
- `Control` Context: fachliche API fuer Fahren, Servo, Sensorik.
- LiveView UI: Joystick, Kamera, Sensoren, Verbindungsstatus, Not-Aus.
- CLI (`mix car ...`): nutzt denselben `Control` Context wie die Web-UI.
- Phoenix PubSub: verteilt Verbindungs- und Telemetrie-Events.

## 6. Protokollregeln (Firmware-kompatibel)
- Frames sind `{...}`-basiert.
- Kommandos sind JSON (`{"N":..., "D1":..., ...}`).
- Relevante Befehle:
  - `N=100`: Stop / Standby.
  - `N=3`: Diskrete Fahrtrichtung + Geschwindigkeit.
  - `N=4`: Differenzielle Motorsteuerung vorwaerts.
    - Wichtig: `D1` = rechtes Rad (Motor A), `D2` = linkes Rad (Motor B).
  - `N=1`: Motor-Einzelsteuerung (fuer Joystick-Kurven ungeeignet).
  - `N=5`: Servo (`D1` = Servo-ID, `D2` = Winkelwert `10..170`).
  - `N=21`: Ultraschall.
  - `N=22`: Liniensensor.
  - `N=102`: Rocker-Befehle.
- Heartbeat `{Heartbeat}` MUSS unterstuetzt werden.

## 7. Funktionsumfang
- Joystick-Echtzeitsteuerung:
  - Winkeldefinition im Uhrzeigersinn.
  - `0°` vorwaerts, `90°` Rechtsdrehung, `180°` rueckwaerts, `270°` Linksdrehung.
  - Lenkeinschlag auf `5°` quantisiert (`-40°..40°`).
  - Geschwindigkeit auf `5%` quantisiert.
  - Loslassen setzt auf Zentrum und stoppt sofort.
- Kamera-Stream-Anzeige.
- Ultraschall- und Linien-Sensoranzeige.
- Verbindungsstatus sichtbar.
- Not-Aus sendet sofort `N=100`.
- Auto-Connect aktiv.
- Kamera-Servo:
  - Slider mit Mitte bei `90°`.
  - `15°`-Schritte links/rechts.
  - UI-Limit `15°..165°`.
- CLI (`mix car ...`):
  - mindestens `connect`, `stop`, `drive`, `turn`, `sensor`, `status`.
  - `turn` mit explizitem Lenkeinschlag und Geschwindigkeit.

## 8. Safety und Laufzeit
- Bei Disconnect/Socket-Fehler: sicherer Stop (`N=100`, falls erreichbar) und Status auf getrennt.
- Bei Inaktivitaet/Tab-Verlassen: Stop senden.
- Steuerbefehle rate-limitieren (typisch 20-30 Hz).
- Sensorik von Steuerung trennen; waehrend Fahrt Sensorpoll drosseln/pausieren.

## 9. Konfiguration
- Via `config/runtime.exs` oder ENV:
  - `CAR_HOST` (Default `192.168.4.1`)
  - `CAR_PORT` (Default `100`)
  - `CAR_STREAM_URL` (Default `http://192.168.4.1:81/stream`)
  - `CONTROL_TICK_MS` (z. B. `33..50`)
  - `SENSOR_POLL_MS` (z. B. `150..300`)
  - `CLI_TIMEOUT_MS`

## 10. Referenzen
- Quellen liegen unter `docs/` (lokal, nicht versioniert).
- Relevante Firmware-Dateien:
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/SmartRobotCarV4.0_V0_20210104/ApplicationFunctionSet_xxx0.cpp`
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/SmartRobotCarV4.0_V0_20210104/DeviceDriverSet_xxx0.cpp`
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/ESP32-WROVER-Camera/ESP32_CameraServer_AP_20210107/ESP32_CameraServer_AP_20210107.ino`
  - `docs/ELEGOO-Smart-Robot-Car-Kit-V4.0/ESP32-WROVER-Camera/ESP32_CameraServer_AP_20210107/app_httpd.cpp`

## 11. Abnahmekriterien (MVP)
- Verbindung wird automatisch aufgebaut und stabil gehalten.
- Joystick steuert reproduzierbar vorwaerts/rueckwaerts/drehen/kurven.
- Loslassen des Joysticks stoppt sofort.
- Kamera-Stream sichtbar.
- Sensorwerte aktualisieren live.
- CLI steuert und liest Sensorik im Terminal.
- Fehlerfaelle sind sichtbar und fuehren zu sicherem Verhalten.

## 12. Verifizierte Implementierungsdetails (normativ)
- Diese Regeln sind in der laufenden Umsetzung validiert und fuer Neu-Implementierungen verbindlich.

- Fahrsteuerungsstrategie:
  - Vorwaerts + Kurve: primaer `N=4`.
  - Rueckwaerts: `N=3 backward` (nicht `N=4`).
  - Drehen auf Stelle: `N=3 left/right`.
  - Stop: immer `N=100`.

- Joystick-Mapping:
  - Eingang `x,y` in `[-1.0,1.0]`.
  - Deadzone nahe Zentrum (`~0.04`).
  - `x` zuerst auf `5°`-Raster quantisieren, dann mischen.
  - Radwerte:
    - `left = y + x_mix`
    - `right = y - x_mix`
  - Normieren auf Maximalbetrag, auf `[-255,255]` mappen, dann auf `5%`-Stufen quantisieren.
  - Kommandowahl:
    - beide >= 0 -> `N=4`
    - beide <= 0 -> `N=3 backward` (bei starkem Lenkwinkel optional `left/right`)
    - gegenlaeufige Vorzeichen -> `N=3 left/right`

- Servo-Regeln:
  - Kamera-Schwenkservo ist `D1=1`.
  - `D2` wird als Winkelwert gesendet (nicht `*10`).
  - Firmware macht intern `Position_angle = D2 / 10` und schreibt danach `10 * Position_angle`.
  - UI quantisiert auf `15°`, Zentrum `90°`, Bereich `15°..165°`.

- Entkopplung und Latenz:
  - Joystick-Events nicht blind senden; deduplizieren ueber stabilen `command_key`.
  - Sensor-Timeout kurz halten (`~250ms`).
  - Sensorpoll waehrend aktiver Fahrt reduzieren.

- UI-Stabilitaet:
  - Joystick-Container mit `phx-update="ignore"` (kein Knob-Reset durch Patches).
  - Keine springenden Inline-Fehlbloecke.
  - Fehler ueber Icon neben Verbindungsbadge.
  - Fuer Badge/Icon festen Platz reservieren (kein Layout-Shift).

- Browser-/Hook-Verhalten:
  - Pointer: `pointerdown`, `pointermove`, `pointerup`, `pointercancel`, `lostpointercapture`.
  - Bei `blur`/`visibilitychange` sofort `joystick_release`.
  - `setPointerCapture`/`releasePointerCapture` defensiv in `try/catch`.
  - Not-Aus-Feedback clientseitig (Hook), sofort sichtbar, unabhaengig vom Roundtrip.
  - Aktueller Not-Aus-Style: Tailwind-UI-nahes rotes Pattern, Text `Not Aus`, kurzer Klick-Schatten-Effekt.

- Netzdiagnose:
  - `:disconnected` bedeutet haeufig fehlende Route zum Fahrzeug.
  - Schnelltest: `nc -vz 192.168.4.1 100`.

## 13. Pflege dieser Datei (verbindlich)
- Jede validierte Verbesserung aus Sessions MUSS in `AGENT.md` nachgefuehrt werden.
- Mindestens zu pflegen:
  - Steuerlogik und Protokoll-Mappings
  - UI/UX-Stabilitaet
  - Latenz-/Performance-Tuning
  - Fehlerbilder + Diagnosepfade
  - Betriebs- und Safety-Regeln
- Formulierungen MUESSEN konkret und reproduzierbar sein (mit Grenzwerten/Schwellen, wo vorhanden).
- Ziel: Neu-Implementierung muss allein mit dieser Datei moeglich sein.
