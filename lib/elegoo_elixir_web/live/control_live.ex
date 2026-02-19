defmodule ElegooElixirWeb.ControlLive do
  use ElegooElixirWeb, :live_view

  alias ElegooElixir.Control

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
      <section class="control-card mb-6 overflow-hidden rounded-2xl p-6 sm:p-8">
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

      <section class="grid gap-6 xl:grid-cols-[1.8fr_1fr]">
        <article class="control-card overflow-hidden rounded-2xl">
          <div class="flex items-center justify-between border-b border-slate-200 px-4 py-3">
            <h2 class="text-sm font-bold uppercase tracking-[0.14em] text-slate-700">Live Kamera</h2>
          </div>
          <img src={@stream_url} alt="Camera stream" class="aspect-video w-full object-cover" />
        </article>

        <article class="control-card rounded-2xl p-5">
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
        </article>
      </section>

      <section class="control-card mt-6 rounded-2xl p-5 sm:p-6">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-sm font-bold uppercase tracking-[0.14em] text-slate-700">
            Joystick-Steuerung
          </h2>
          <button
            class="rounded-2xl bg-rose-600 px-8 py-5 text-xl font-black tracking-wide text-white shadow-lg shadow-rose-200 transition hover:bg-rose-500"
            phx-click="stop"
          >
            Not-Aus
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
          </div>
        </div>
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

  defp clamp_float(value, min, _max) when value < min, do: min
  defp clamp_float(value, _min, max) when value > max, do: max
  defp clamp_float(value, _min, _max), do: value

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
end
