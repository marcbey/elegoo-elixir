defmodule ElegooElixir.Speech.CommandExecutor do
  @moduledoc """
  Executes parsed speech intents via the shared Control context.
  """

  alias ElegooElixir.CarProtocol
  alias ElegooElixir.Control

  defmodule State do
    @moduledoc false
    defstruct speed: 120, camera_angle: 90
  end

  @type execution_result :: %{
          message: String.t(),
          motion?: boolean(),
          motion_key: term() | nil
        }

  @spec initial_state() :: State.t()
  def initial_state do
    %State{
      speed: speech_config(:voice_default_speed, 120),
      camera_angle: Control.camera_servo_center_deg()
    }
  end

  @spec execute(map(), State.t()) ::
          {:ok, execution_result(), State.t()} | {:error, term(), State.t()}
  def execute(intent, %State{} = state) when is_map(intent) do
    case intent do
      %{kind: :stop} ->
        case Control.stop() do
          {:ok, _} ->
            {:ok, %{message: "Stop ausgefuehrt", motion?: false, motion_key: :stop}, state}

          {:error, reason} ->
            {:error, reason, state}
        end

      %{kind: :drive, direction: direction} ->
        execute_drive(direction, state.speed, state)

      %{kind: :spin, direction: direction} ->
        execute_spin(direction, state.speed, state)

      %{kind: :speed_adjust, delta: delta} ->
        new_speed = CarProtocol.clamp(state.speed + delta, 0, 255)
        new_state = %{state | speed: new_speed}

        {:ok, %{message: "Tempo auf #{new_speed} gesetzt", motion?: false, motion_key: nil},
         new_state}

      %{kind: :set_speed, value: value} ->
        new_speed = CarProtocol.clamp(value, 0, 255)
        new_state = %{state | speed: new_speed}

        {:ok, %{message: "Tempo auf #{new_speed} gesetzt", motion?: false, motion_key: nil},
         new_state}

      %{kind: :camera_center} ->
        angle = Control.camera_servo_center_deg()
        set_camera(angle, state)

      %{kind: :camera_step, direction: :left} ->
        set_camera(state.camera_angle - 15, state)

      %{kind: :camera_step, direction: :right} ->
        set_camera(state.camera_angle + 15, state)

      %{kind: :camera_set_angle, value: value} ->
        set_camera(value, state)

      %{kind: :sensor, sensor: :ultrasound} ->
        case Control.sensor(:ultrasound) do
          {:ok, value} ->
            {:ok, %{message: "Ultraschall: #{inspect(value)}", motion?: false, motion_key: nil},
             state}

          {:error, reason} ->
            {:error, reason, state}
        end

      %{kind: :sensor, sensor: :line} ->
        case Control.sensor(:line) do
          {:ok, value} ->
            {:ok, %{message: "Liniensensor: #{inspect(value)}", motion?: false, motion_key: nil},
             state}

          {:error, reason} ->
            {:error, reason, state}
        end

      _ ->
        {:error, :unsupported_intent, state}
    end
  end

  defp execute_drive(direction, speed, state) do
    case Control.drive(direction, speed) do
      {:ok, _} ->
        {:ok,
         %{
           message: "Fahre #{human_direction(direction)} mit Tempo #{speed}",
           motion?: true,
           motion_key: {:drive, direction, speed}
         }, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp execute_spin(direction, speed, state) do
    case Control.drive(direction, speed) do
      {:ok, _} ->
        {:ok,
         %{
           message: "Drehe #{human_direction(direction)} mit Tempo #{speed}",
           motion?: true,
           motion_key: {:spin, direction, speed}
         }, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp set_camera(angle, state) do
    case Control.set_camera_servo(angle) do
      {:ok, _} ->
        quantized = quantize_camera_angle(angle)
        new_state = %{state | camera_angle: quantized}

        {:ok,
         %{
           message: "Kamera auf #{quantized} Grad gesetzt",
           motion?: false,
           motion_key: nil
         }, new_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp quantize_camera_angle(angle) do
    angle
    |> CarProtocol.clamp(15, 165)
    |> Kernel./(15)
    |> round()
    |> Kernel.*(15)
    |> CarProtocol.clamp(15, 165)
  end

  defp human_direction(:forward), do: "vorwaerts"
  defp human_direction(:backward), do: "rueckwaerts"
  defp human_direction(:left), do: "links"
  defp human_direction(:right), do: "rechts"

  defp speech_config(key, default) do
    Application.get_env(:elegoo_elixir, :speech, [])
    |> Keyword.get(key, default)
  end
end
