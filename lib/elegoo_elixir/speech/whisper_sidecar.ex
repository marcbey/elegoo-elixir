defmodule ElegooElixir.Speech.WhisperSidecar do
  @moduledoc """
  Optional sidecar process that starts a local whisper.cpp HTTP server
  together with the Phoenix app.
  """

  use GenServer

  require Logger

  defmodule State do
    @moduledoc false
    defstruct enabled?: false,
              launch_cmd: nil,
              restart_ms: 5_000,
              port: nil,
              retry_timer: nil
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %State{
      enabled?: speech_config(:whisper_autostart, false),
      launch_cmd: speech_config(:whisper_launch_cmd, nil),
      restart_ms: speech_config(:whisper_restart_ms, 5_000),
      port: nil,
      retry_timer: nil
    }

    {:ok, maybe_start(state)}
  end

  @impl true
  def handle_info(:start_whisper, state) do
    {:noreply, maybe_start(%{state | retry_timer: nil})}
  end

  def handle_info({port, {:data, data}}, %State{port: port} = state) do
    if Logger.compare_levels(Logger.level(), :debug) != :gt do
      data
      |> to_string()
      |> String.trim()
      |> log_sidecar_output()
    end

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %State{port: port} = state) do
    Logger.warning("Whisper sidecar exited with status #{status}.")
    {:noreply, schedule_restart(%{state | port: nil})}
  end

  def handle_info({:EXIT, port, reason}, %State{port: port} = state) do
    Logger.warning("Whisper sidecar process exited: #{inspect(reason)}")
    {:noreply, schedule_restart(%{state | port: nil})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp maybe_start(%State{enabled?: false} = state), do: state
  defp maybe_start(%State{port: port} = state) when is_port(port), do: state

  defp maybe_start(%State{launch_cmd: launch_cmd} = state) when launch_cmd in [nil, ""] do
    Logger.warning(
      "Whisper autostart is enabled but WHISPER_LAUNCH_CMD is not configured. " <>
        "Configure WHISPER_LAUNCH_CMD or disable WHISPER_AUTOSTART."
    )

    schedule_restart(state)
  end

  defp maybe_start(%State{launch_cmd: launch_cmd} = state) do
    Logger.info("Starting whisper sidecar: #{launch_cmd}")

    try do
      port =
        Port.open({:spawn, launch_cmd}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout
        ])

      %{state | port: port}
    rescue
      error ->
        Logger.error("Failed to start whisper sidecar: #{inspect(error)}")
        schedule_restart(state)
    end
  end

  defp schedule_restart(%State{enabled?: false} = state), do: state

  defp schedule_restart(%State{retry_timer: timer_ref} = state) when is_reference(timer_ref),
    do: state

  defp schedule_restart(%State{restart_ms: restart_ms} = state) do
    timer_ref = Process.send_after(self(), :start_whisper, restart_ms)
    %{state | retry_timer: timer_ref}
  end

  defp speech_config(key, default) do
    Application.get_env(:elegoo_elixir, :speech, [])
    |> Keyword.get(key, default)
  end

  defp log_sidecar_output(""), do: :ok
  defp log_sidecar_output(line), do: Logger.debug("whisper sidecar> #{line}")
end
