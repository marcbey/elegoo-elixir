# Elegoo Elixir

Browser- und Terminal-Steuerung fuer das Elegoo Smart Robot Car V4.0 mit Phoenix + LiveView und `:gen_tcp`.

Aktuell laeuft die App komplett ohne Datenbank.

## Features

- LiveView Web-UI mit:
  - Joystick-Fahrsteuerung (Lenkeinschlag in `5°`, Geschwindigkeit in `5%`)
  - Not-Aus (`N=100`)
  - Kamera-Live-Stream
  - Ultraschall- und Linien-Sensoren
  - Kamera-Servo-Slider (`15°`-Raster, Zentrum `90°`)
- Terminal-CLI (`mix car ...`) fuer Fahr- und Sensor-Kommandos

## Setup

```bash
mix deps.get
```

## Web UI starten

```bash
mix phx.server
```

Dann im Browser: [http://localhost:4000](http://localhost:4000)

## CLI verwenden

Die CLI laeuft headless (ohne Webserver/DB-Start) und nutzt denselben Control-Layer:

```bash
# global options immer vor dem Subcommand:
# mix car [--host HOST] [--port PORT] [--timeout MS] <command> [command options]

mix car status
mix car connect
mix car stop
mix car drive --direction forward --speed 120
mix car turn --steer 40 --speed 160
mix car sensor --type ultrasound
mix car sensor --type line --side all
mix car --host 192.168.4.1 --port 100 --timeout 1500 status
```

Aktuell ist die Kamera-Servo-Steuerung in der Web-UI verfuegbar (nicht als eigener CLI-Subcommand).

## Tests

```bash
mix test
```

## Relevante ENV-Konfiguration

```bash
CAR_HOST=192.168.4.1
CAR_PORT=100
CAR_STREAM_URL=http://192.168.4.1:81/stream
CAR_RECONNECT_MS=1000
CONTROL_TICK_MS=40
SENSOR_POLL_MS=250
CLI_TIMEOUT_MS=1500
```
