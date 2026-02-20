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
  - Sprachsteuerung (Always-On im Browser, Transkription via lokalem `whisper.cpp`-Dienst)
- Terminal-CLI (`mix car ...`) fuer Fahr-, Sensor- und Kamera-Servo-Kommandos

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
mix car servo --angle 120
mix car servo --center
mix car sensor --type ultrasound
mix car sensor --type line --side all
mix car voice --text "drive forward" --dry-run
mix car --host 192.168.4.1 --port 100 --timeout 1500 status
```

## Sprachsteuerung (lokales whisper.cpp)

Die Browser-UI lauscht dauerhaft (hands-free) auf Sprachkommandos. Der Flow ist:

1. Browser nimmt Audio auf.
2. Audio-Upload an `POST /api/speech/transcribe`.
3. Backend ruft lokalen whisper.cpp-Dienst auf.
4. Transkript wird deterministisch in Fahrbefehl gemappt und ueber `Control` ausgefuehrt.

### Beispiel: whisper.cpp Server starten

```bash
# Beispielhafte whisper.cpp-Server-Startparameter (abh. von deiner Installation)
./server \
  -m /path/to/ggml-base.bin \
  --host 127.0.0.1 \
  --port 8088
```

Standardmaessig erwartet die App den Endpoint `http://127.0.0.1:8088/inference`.

### Optional: whisper automatisch mit `mix phx.server` starten

Setze dazu `WHISPER_AUTOSTART=true` und hinterlege den kompletten Startbefehl:

```bash
export WHISPER_AUTOSTART=true
export WHISPER_LAUNCH_CMD="/path/to/whisper.cpp/server -m /path/to/ggml-base.bin --host 127.0.0.1 --port 8088"
mix phx.server
```

Der Sidecar-Prozess wird beim App-Start gestartet und bei Absturz automatisch neu versucht.

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
STT_PROVIDER=whisper_local
STT_BASE_URL=http://127.0.0.1:8088
STT_PATH=/inference
STT_TIMEOUT_MS=10000
STT_LANGUAGE=en
WHISPER_AUTOSTART=false
WHISPER_LAUNCH_CMD="/path/to/whisper.cpp/server -m /path/to/ggml-base.bin --host 127.0.0.1 --port 8088"
WHISPER_RESTART_MS=5000
VOICE_MAX_CLIP_MS=4500
VOICE_MIN_COMMAND_INTERVAL_MS=250
VOICE_DEFAULT_SPEED=120
```
