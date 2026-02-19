defmodule ElegooElixir.CarProtocol do
  @moduledoc """
  Protocol helpers for the Elegoo robot control socket (`{...}` framed messages).
  """

  @type direction :: :left | :right | :forward | :backward
  @type line_sensor :: :left | :middle | :right

  @spec heartbeat_frame() :: binary()
  def heartbeat_frame, do: "{Heartbeat}"

  @spec encode_json(map()) :: {:ok, binary()} | {:error, term()}
  def encode_json(payload) when is_map(payload) do
    case Jason.encode(payload) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_command() :: map()
  def stop_command, do: %{"N" => 100}

  @spec drive_command(direction(), integer()) :: map()
  def drive_command(direction, speed) do
    %{
      "N" => 3,
      "D1" => drive_direction_code(direction),
      "D2" => clamp(speed, 0, 255)
    }
  end

  @spec motor_speed_command(integer(), integer()) :: map()
  def motor_speed_command(left_speed, right_speed) do
    %{
      "N" => 4,
      # Firmware maps D1 -> motor A (right wheel) and D2 -> motor B (left wheel).
      "D1" => clamp(right_speed, 0, 255),
      "D2" => clamp(left_speed, 0, 255)
    }
  end

  @spec motor_control_command(0 | 1 | 2, integer(), 0 | 1 | 2) :: map()
  def motor_control_command(selection, speed, direction)
      when selection in [0, 1, 2] and direction in [0, 1, 2] do
    %{
      "N" => 1,
      "D1" => selection,
      "D2" => clamp(speed, 0, 255),
      "D3" => direction
    }
  end

  @spec servo_command(1 | 2 | 3, integer()) :: map()
  def servo_command(servo_id, angle_deg) when servo_id in [1, 2, 3] do
    %{
      "N" => 5,
      "D1" => servo_id,
      # Firmware computes Position_angle = D2 / 10 and then writes 10 * Position_angle.
      # Therefore D2 must be sent in the 10..170 scale directly (not multiplied by 10).
      "D2" => clamp(angle_deg, 10, 170)
    }
  end

  @spec ultrasound_command(1 | 2) :: map()
  def ultrasound_command(mode \\ 2) when mode in [1, 2] do
    %{"N" => 21, "D1" => mode}
  end

  @spec line_sensor_command(line_sensor()) :: map()
  def line_sensor_command(sensor) do
    %{"N" => 22, "D1" => line_sensor_code(sensor)}
  end

  @spec decode_frame(binary()) ::
          :heartbeat | {:ok, binary()} | {:response, binary(), binary()} | {:raw, binary()}
  def decode_frame("{Heartbeat}"), do: :heartbeat

  def decode_frame(frame) when is_binary(frame) do
    content =
      frame
      |> String.trim()
      |> String.trim_leading("{")
      |> String.trim_trailing("}")

    cond do
      content == "ok" ->
        {:ok, "ok"}

      String.contains?(content, "_") ->
        [serial, payload] = String.split(content, "_", parts: 2)

        if serial =~ ~r/^\d+$/ do
          {:response, serial, payload}
        else
          {:raw, content}
        end

      true ->
        {:raw, content}
    end
  end

  @spec drive_direction_code(direction()) :: 1 | 2 | 3 | 4
  def drive_direction_code(:left), do: 1
  def drive_direction_code(:right), do: 2
  def drive_direction_code(:forward), do: 3
  def drive_direction_code(:backward), do: 4

  @spec line_sensor_code(line_sensor()) :: 0 | 1 | 2
  def line_sensor_code(:left), do: 0
  def line_sensor_code(:middle), do: 1
  def line_sensor_code(:right), do: 2

  @spec clamp(integer(), integer(), integer()) :: integer()
  def clamp(value, min, _max) when value < min, do: min
  def clamp(value, _min, max) when value > max, do: max
  def clamp(value, _min, _max), do: value
end
