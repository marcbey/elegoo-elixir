defmodule ElegooElixirWeb.ControlLive do
  use ElegooElixirWeb, :live_view

  alias ElegooElixir.CarProtocol
  alias ElegooElixir.Control
  alias ElegooElixir.Speech.CommandExecutor
  alias ElegooElixir.Speech.CommandParser
  alias ElegooElixir.Speech.SafetyGuard

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      _ = Control.subscribe()
      Control.connect()
      schedule_sensor_poll()
    end

    car_config = Application.get_env(:elegoo_elixir, :car, [])

    {:ok,
     socket
     |> assign(:status, Control.status())
     |> assign(:stream_url, Keyword.get(car_config, :stream_url, "http://192.168.4.1:81/stream"))
     |> assign(:joystick, %{x: 0.0, y: 0.0})
     |> assign(:steer_deg, 0)
     |> assign(:last_drive_command, :stop)
     |> assign(:driving_active, false)
     |> assign(:camera_pan, 0)
     |> assign(:camera_angle, Control.camera_servo_center_deg())
     |> assign(:voice_state, :idle)
     |> assign(:voice_transcript, nil)
     |> assign(:voice_intent, nil)
     |> assign(:voice_feedback, nil)
     |> assign(:voice_executor_state, CommandExecutor.initial_state())
     |> assign(:voice_safety_guard, SafetyGuard.new())
     |> assign(:ultrasound, nil)
     |> assign(:line_sensors, %{left: nil, middle: nil, right: nil})
     |> assign(:last_error, nil)}
  end

  @impl true
  def handle_event("connect", _params, socket) do
    Control.connect()
    {:noreply, assign(socket, :status, Control.status())}
  end

  def handle_event("stop", _params, socket) do
    socket =
      socket
      |> assign(:joystick, %{x: 0.0, y: 0.0})
      |> assign(:steer_deg, 0)
      |> assign(:last_drive_command, :stop)
      |> assign(:driving_active, false)
      |> maybe_assign_error(Control.stop())

    {:noreply, assign(socket, :status, Control.status())}
  end

  def handle_event("emergency_stop", _params, socket) do
    socket =
      socket
      |> assign(:joystick, %{x: 0.0, y: 0.0})
      |> assign(:steer_deg, 0)
      |> assign(:last_drive_command, :stop)
      |> assign(:driving_active, false)
      |> maybe_assign_error(Control.stop())
      |> assign(:status, Control.status())

    {:noreply, socket}
  end

  def handle_event("joystick_move", params, socket) do
    x = params |> Map.get("x", "0.0") |> parse_float(0.0) |> clamp_float(-1.0, 1.0)
    y = params |> Map.get("y", "0.0") |> parse_float(0.0) |> clamp_float(-1.0, 1.0)
    vector = Control.joystick_vector(x, y)

    result =
      if vector.command_key == socket.assigns.last_drive_command do
        {:ok, :unchanged}
      else
        Control.execute_joystick_vector(vector)
      end

    socket =
      socket
      |> assign(:joystick, %{x: vector.x, y: vector.y})
      |> assign(:steer_deg, vector.steer_deg)
      |> assign(:last_drive_command, vector.command_key)
      |> assign(:driving_active, vector.command_key != :stop)
      |> maybe_assign_error(result)
      |> assign(:status, Control.status())

    {:noreply, socket}
  end

  def handle_event("joystick_release", _params, socket) do
    socket =
      socket
      |> assign(:joystick, %{x: 0.0, y: 0.0})
      |> assign(:steer_deg, 0)
      |> assign(:last_drive_command, :stop)
      |> assign(:driving_active, false)
      |> maybe_assign_error(Control.stop())
      |> assign(:status, Control.status())

    {:noreply, socket}
  end

  def handle_event("camera_pan", %{"pan" => pan}, socket) do
    pan = pan |> parse_int(0) |> quantize_camera_pan()
    angle = Control.camera_servo_center_deg() + pan

    result =
      if angle == socket.assigns.camera_angle do
        {:ok, :unchanged}
      else
        Control.set_camera_servo(angle)
      end

    socket =
      socket
      |> assign(:camera_pan, pan)
      |> assign(:camera_angle, angle)
      |> maybe_assign_error(result)
      |> assign(:status, Control.status())

    {:noreply, socket}
  end

  def handle_event("voice_state", %{"state" => state}, socket) do
    voice_state =
      case state do
        "listening" -> :listening
        "processing" -> :processing
        "unsupported" -> :unsupported
        _ -> :idle
      end

    {:noreply, assign(socket, :voice_state, voice_state)}
  end

  def handle_event("voice_error", %{"message" => message}, socket) do
    socket =
      socket
      |> assign(:voice_state, :idle)
      |> assign(:voice_feedback, "Sprachfehler: #{message}")

    {:noreply, socket}
  end

  def handle_event("voice_transcript", %{"text" => text}, socket) do
    transcript = text |> to_string() |> String.trim()

    socket =
      socket
      |> assign(:voice_state, :idle)
      |> assign(:voice_transcript, transcript)

    cond do
      transcript == "" ->
        {:noreply, assign(socket, :voice_feedback, "Keine Sprache erkannt.")}

      true ->
        execute_voice_transcript(transcript, socket)
    end
  end

  @impl true
  def handle_info(:poll_sensors, socket) do
    initial_status = Control.status()

    socket =
      if socket.assigns.driving_active do
        socket
      else
        poll_sensor_values(initial_status, socket)
      end

    {:noreply, assign(socket, :status, Control.status())}
  end

  def handle_info({:car_event, _event}, socket) do
    {:noreply, assign(socket, :status, Control.status())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="control-shell mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <section class="control-card mb-6 overflow-hidden rounded-2xl p-5">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-[0.22em] text-teal-700">
              Elegoo V4 Control
            </p>
            <h1 class="text-3xl font-black tracking-tight text-slate-900 sm:text-4xl">
              Fahrsteuerung und Sensor-Hub
            </h1>
            <p class="text-sm text-slate-600">
              TCP: {@status.host}:{@status.port}
              <span class="ml-2 inline-flex items-center gap-2 whitespace-nowrap align-middle">
                <span class={[
                  "inline-flex min-w-[6.5rem] justify-center rounded-full px-3 py-1 text-xs font-bold",
                  status_badge_class(@status.connected)
                ]}>
                  {status_label(@status.connected)}
                </span>
                <span
                  class={[
                    "inline-flex size-6 items-center justify-center rounded-full ring-1 transition",
                    if(@last_error || @status.last_error,
                      do: "bg-amber-100 text-amber-700 ring-amber-200 opacity-100",
                      else: "bg-transparent text-transparent ring-transparent opacity-0"
                    )
                  ]}
                  title={status_error_message(@last_error, @status.last_error)}
                  aria-label="Fehler vorhanden"
                >
                  <.icon name="hero-exclamation-triangle-mini" class="size-4" />
                </span>
              </span>
            </p>
          </div>
        </div>
      </section>

      <section class="grid gap-6 lg:grid-cols-2 lg:items-start">
        <article class="control-card overflow-hidden rounded-2xl">
          <div class="flex items-center justify-between border-b border-slate-200 px-5 py-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.14em] text-slate-700">Live Kamera</h2>
          </div>
          <img src={@stream_url} alt="Camera stream" class="aspect-video w-full object-cover" />
        </article>

        <section class="control-card rounded-2xl p-5">
          <div class="mb-4 flex flex-wrap items-start justify-between gap-2">
            <h2 class="text-sm font-bold uppercase tracking-[0.14em] text-slate-700">
              Joystick-Steuerung
            </h2>
            <button
              id="emergency-stop-btn"
              class="e-stop-btn inline-flex items-center justify-center rounded-xl bg-rose-600 px-8 py-5 text-xl font-extrabold tracking-wide text-white shadow-lg shadow-rose-600/30 transition hover:bg-rose-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-600 active:bg-rose-700"
              phx-hook="EmergencyStopButton"
              phx-click="emergency_stop"
            >
              Not Aus
            </button>
          </div>

          <div class="grid gap-6 lg:grid-cols-[1.4fr_1fr] lg:items-center">
            <div id="drive-joystick" phx-hook="Joystick" phx-update="ignore" class="joystick-shell">
              <div
                class="joystick-area"
                data-joystick-area
                role="application"
                aria-label="Fahr-Joystick"
              >
                <div class="joystick-knob" data-joystick-knob></div>
              </div>
            </div>

            <div class="space-y-3">
              <div class="rounded-xl bg-slate-50 p-4">
                <p class="text-xs font-semibold uppercase tracking-[0.11em] text-slate-500">
                  Fahrzustand
                </p>
                <p class="mt-1 text-lg font-black text-slate-900">{throttle_label(@joystick)}</p>
                <p class={[
                  "min-h-5 text-sm text-slate-600",
                  if(hide_straight_label?(@joystick), do: "invisible", else: "visible")
                ]}>
                  {steering_label(@joystick)}
                </p>
              </div>
              <div class="rounded-xl bg-slate-50 p-4">
                <p class="text-xs font-semibold uppercase tracking-[0.11em] text-slate-500">
                  Kamera (Servo)
                </p>
                <p class="mt-1 text-lg font-black text-slate-900">{@camera_angle}°</p>
                <input
                  id="camera-pan-slider"
                  type="range"
                  name="pan"
                  min="-75"
                  max="75"
                  step="15"
                  value={@camera_pan}
                  class="mt-3 w-full"
                  phx-hook="CameraPanSlider"
                  aria-label="Kamera seitlich schwenken"
                />
                <div class="mt-2 flex justify-between text-xs font-semibold uppercase text-slate-500">
                  <span>Links</span>
                  <span>Mitte</span>
                  <span>Rechts</span>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <div class="rounded-xl bg-slate-50 p-3">
                  <p class="text-xs font-semibold uppercase text-slate-500">Geschwindigkeit</p>
                  <p class="mt-1 text-xl font-black text-slate-900">
                    {joystick_power_percent(@joystick)}%
                  </p>
                </div>
                <div class="rounded-xl bg-slate-50 p-3">
                  <p class="text-xs font-semibold uppercase text-slate-500">Lenkeinschlag</p>
                  <p class="mt-1 text-xl font-black text-slate-900">
                    {@steer_deg}°
                  </p>
                </div>
              </div>
              <div
                id="voice-handsfree-panel"
                class="rounded-xl bg-slate-50 p-4"
                data-voice-panel
                phx-hook="SpeechPushToTalk"
                data-endpoint={~p"/api/speech/transcribe"}
                data-max-clip-ms={voice_max_clip_ms()}
              >
                <div class="flex items-center justify-between gap-3">
                  <p class="text-xs font-semibold uppercase tracking-[0.11em] text-slate-500">
                    Sprache (Whisper)
                  </p>
                  <span class="rounded-full bg-teal-100 px-3 py-1 text-[11px] font-bold uppercase text-teal-800">
                    Always On
                  </span>
                </div>

                <div class="mt-3">
                  <p class="text-[11px] font-semibold uppercase tracking-[0.08em] text-slate-500">
                    Mikro Pegel
                  </p>
                  <div
                    class="voice-level-meter mt-1"
                    role="meter"
                    aria-label="Mikrofon Ausschlag"
                    aria-valuemin="0"
                    aria-valuemax="100"
                    aria-valuenow="0"
                    data-voice-level-meter
                  >
                    <div class="voice-level-fill" data-voice-level-fill></div>
                  </div>
                </div>

                <p class="mt-2 text-sm font-semibold text-slate-900">
                  {voice_state_label(@voice_state)}
                </p>
                <p class="mt-1 min-h-5 text-sm text-slate-600">
                  {voice_feedback_label(@voice_feedback)}
                </p>
                <p class="mt-2 text-xs text-slate-500">
                  Letztes Transkript:
                  <span class="font-semibold text-slate-700">{@voice_transcript || "-"}</span>
                </p>
                <p class="text-xs text-slate-500">
                  Intent: <span class="font-semibold text-slate-700">{@voice_intent || "-"}</span>
                </p>
                <p class="text-xs text-slate-500">
                  Voice-Tempo:
                  <span class="font-semibold text-slate-700">{@voice_executor_state.speed}</span>
                </p>
              </div>
            </div>
          </div>
        </section>
      </section>

      <section class="control-card mt-6 rounded-2xl p-5">
        <h2 class="mb-4 text-sm font-bold uppercase tracking-[0.14em] text-slate-700">Sensoren</h2>
        <dl class="space-y-3">
          <div class="rounded-xl bg-slate-50 p-3">
            <dt class="text-xs font-semibold uppercase text-slate-500">Ultraschall</dt>
            <dd class="mt-1 text-xl font-black text-slate-900">{format_sensor(@ultrasound)}</dd>
          </div>
          <div class="grid grid-cols-3 gap-2">
            <div class="rounded-xl bg-slate-50 p-3 text-center">
              <p class="text-[11px] font-semibold uppercase text-slate-500">Linie L</p>
              <p class="mt-1 text-lg font-bold text-slate-900">
                {format_sensor(@line_sensors.left)}
              </p>
            </div>
            <div class="rounded-xl bg-slate-50 p-3 text-center">
              <p class="text-[11px] font-semibold uppercase text-slate-500">Linie M</p>
              <p class="mt-1 text-lg font-bold text-slate-900">
                {format_sensor(@line_sensors.middle)}
              </p>
            </div>
            <div class="rounded-xl bg-slate-50 p-3 text-center">
              <p class="text-[11px] font-semibold uppercase text-slate-500">Linie R</p>
              <p class="mt-1 text-lg font-bold text-slate-900">
                {format_sensor(@line_sensors.right)}
              </p>
            </div>
          </div>
        </dl>
      </section>
    </main>
    """
  end

  defp schedule_sensor_poll do
    car_config = Application.get_env(:elegoo_elixir, :car, [])
    interval = Keyword.get(car_config, :sensor_poll_ms, 250)
    :timer.send_interval(interval, :poll_sensors)
  end

  defp poll_sensor_values(initial_status, socket) do
    if initial_status.connected do
      with {:ok, ultrasound} <- Control.sensor(:ultrasound),
           {:ok, line} <- Control.sensor(:line) do
        socket
        |> assign(:ultrasound, ultrasound)
        |> assign(:line_sensors, line)
        |> assign(:last_error, nil)
      else
        {:error, reason} ->
          assign(socket, :last_error, "Sensorfehler: #{inspect(reason)}")
      end
    else
      Control.connect()
      socket
    end
  end

  defp execute_voice_transcript(transcript, socket) do
    with {:ok, intent} <- CommandParser.parse(transcript),
         {:ok, safety_guard} <- allow_voice_command(intent, socket.assigns.voice_safety_guard),
         {:ok, execution, executor_state} <-
           CommandExecutor.execute(intent, socket.assigns.voice_executor_state) do
      socket =
        socket
        |> assign(:voice_intent, CommandParser.describe_intent(intent))
        |> assign(:voice_feedback, execution.message)
        |> assign(:voice_executor_state, executor_state)
        |> assign(:voice_safety_guard, safety_guard)
        |> maybe_sync_camera_from_executor(executor_state)
        |> sync_drive_state(execution)
        |> assign(:status, Control.status())
        |> assign(:last_error, nil)

      {:noreply, socket}
    else
      {:error, :empty} ->
        {:noreply, assign(socket, :voice_feedback, "Kein gueltiger Text erkannt.")}

      {:error, :unknown} ->
        {:noreply, assign(socket, :voice_feedback, "Unbekanntes Sprachkommando.")}

      {:skip, :duplicate, safety_guard} ->
        socket =
          socket
          |> assign(:voice_safety_guard, safety_guard)
          |> assign(:voice_feedback, "Befehl ignoriert (Duplikat).")

        {:noreply, socket}

      {:skip, :rate_limited, safety_guard} ->
        socket =
          socket
          |> assign(:voice_safety_guard, safety_guard)
          |> assign(:voice_feedback, "Befehl ignoriert (zu schnell hintereinander).")

        {:noreply, socket}

      {:error, reason, executor_state} ->
        socket =
          socket
          |> assign(:voice_executor_state, executor_state)
          |> assign(:voice_feedback, "Sprachbefehl fehlgeschlagen: #{inspect(reason)}")
          |> assign(:status, Control.status())
          |> maybe_assign_error({:error, reason})

        {:noreply, socket}
    end
  end

  defp allow_voice_command(%{kind: :stop} = intent, guard) do
    intent
    |> CommandParser.intent_key()
    |> then(&SafetyGuard.allow?(guard, &1, bypass: true))
    |> reduce_safety_result()
  end

  defp allow_voice_command(intent, guard) do
    intent
    |> CommandParser.intent_key()
    |> then(&SafetyGuard.allow?(guard, &1))
    |> reduce_safety_result()
  end

  defp reduce_safety_result({:ok, guard}), do: {:ok, guard}
  defp reduce_safety_result({:skip, reason, guard}), do: {:skip, reason, guard}

  defp sync_drive_state(socket, %{motion_key: :stop}) do
    socket
    |> assign(:joystick, %{x: 0.0, y: 0.0})
    |> assign(:steer_deg, 0)
    |> assign(:last_drive_command, :stop)
    |> assign(:driving_active, false)
  end

  defp sync_drive_state(socket, %{motion?: true, motion_key: motion_key}) do
    socket
    |> assign(:last_drive_command, motion_key)
    |> assign(:driving_active, true)
  end

  defp sync_drive_state(socket, _execution), do: socket

  defp maybe_sync_camera_from_executor(socket, %{camera_angle: camera_angle}) do
    pan = quantize_camera_pan(camera_angle - Control.camera_servo_center_deg())

    socket
    |> assign(:camera_angle, camera_angle)
    |> assign(:camera_pan, pan)
  end

  defp maybe_assign_error(socket, {:ok, _result}), do: assign(socket, :last_error, nil)

  defp maybe_assign_error(socket, {:error, :disconnected}) do
    assign(
      socket,
      :last_error,
      "Befehl fehlgeschlagen: keine TCP-Verbindung. Bitte Fahrzeug-WLAN und Server-Netzwerkroute pruefen."
    )
  end

  defp maybe_assign_error(socket, {:error, reason}),
    do: assign(socket, :last_error, "Befehl fehlgeschlagen: #{inspect(reason)}")

  defp parse_float(value, default) do
    case Float.parse(to_string(value)) do
      {parsed, _rest} -> parsed
      _ -> default
    end
  end

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {parsed, _rest} -> parsed
      _ -> default
    end
  end

  defp clamp_float(value, min, _max) when value < min, do: min
  defp clamp_float(value, _min, max) when value > max, do: max
  defp clamp_float(value, _min, _max), do: value

  defp quantize_camera_pan(pan) do
    pan
    |> CarProtocol.clamp(-75, 75)
    |> Kernel./(15)
    |> round()
    |> Kernel.*(15)
    |> CarProtocol.clamp(-75, 75)
  end

  defp joystick_power_percent(%{x: x, y: y}) do
    magnitude = :math.sqrt(x * x + y * y)
    magnitude = clamp_float(magnitude, 0.0, 1.0)

    magnitude
    |> Kernel.*(100.0)
    |> Kernel./(5.0)
    |> round()
    |> Kernel.*(5)
  end

  defp throttle_label(%{y: y}) when y > 0.08, do: "Vorwaerts"
  defp throttle_label(%{y: y}) when y < -0.08, do: "Rueckwaerts"
  defp throttle_label(_joystick), do: "Stopp"

  defp steering_label(%{x: x}) when x > 0.08, do: "Rechtskurve"
  defp steering_label(%{x: x}) when x < -0.08, do: "Linkskurve"
  defp steering_label(_joystick), do: "Geradeaus"

  defp hide_straight_label?(joystick),
    do: throttle_label(joystick) == "Stopp" and steering_label(joystick) == "Geradeaus"

  defp format_sensor(nil), do: "-"
  defp format_sensor(value), do: to_string(value)

  defp status_label(true), do: "Verbunden"
  defp status_label(false), do: "Getrennt"

  defp status_badge_class(true), do: "bg-emerald-100 text-emerald-800 ring-1 ring-emerald-200"
  defp status_badge_class(false), do: "bg-rose-100 text-rose-800 ring-1 ring-rose-200"

  defp status_error_message(last_error, _status_error) when is_binary(last_error), do: last_error
  defp status_error_message(_last_error, status_error), do: "Fehler: #{inspect(status_error)}"

  defp voice_state_label(:listening), do: "Aufnahme laeuft"
  defp voice_state_label(:processing), do: "Transkription laeuft"
  defp voice_state_label(:unsupported), do: "Browser unterstuetzt kein Mikrofon-Recording"
  defp voice_state_label(_), do: "Bereit"

  defp voice_feedback_label(nil), do: "-"
  defp voice_feedback_label(value), do: value

  defp voice_max_clip_ms do
    Application.get_env(:elegoo_elixir, :speech, [])
    |> Keyword.get(:voice_max_clip_ms, 4_500)
  end
end
