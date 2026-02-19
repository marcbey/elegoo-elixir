defmodule ElegooElixir.Control do
  @moduledoc """
  High-level car control API shared by LiveView and CLI.
  """

  alias ElegooElixir.CarProtocol
  alias ElegooElixir.CarTcpClient

  @type drive_direction :: :left | :right | :forward | :backward
  @type joystick_vector :: %{
          x: float(),
          y: float(),
          steer_deg: integer(),
          left_speed: integer(),
          right_speed: integer(),
          command: joystick_command(),
          command_key: term()
        }
  @type joystick_command ::
          :stop
          | {:drive, drive_direction(), integer()}
          | {:motor_speed, integer(), integer()}

  @max_steer_deg 40
  @steer_step_deg 5
  @speed_step_percent 5
  @speed_step_value max(1, round(255 * (@speed_step_percent / 100)))
  @joystick_deadzone 0.04
  @sensor_timeout_ms 250
  @reverse_spin_threshold_deg 25

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: CarTcpClient.subscribe()

  @spec connect() :: :ok
  def connect, do: CarTcpClient.connect()

  @spec status() :: map()
  def status, do: CarTcpClient.status()

  @spec stop() :: {:ok, binary()} | {:error, term()}
  def stop do
    CarTcpClient.send_command(CarProtocol.stop_command())
  end

  @spec drive(drive_direction(), integer()) :: {:ok, binary()} | {:error, term()}
  def drive(direction, speed) when direction in [:left, :right, :forward, :backward] do
    speed = CarProtocol.clamp(speed, 0, 255)
    command = CarProtocol.drive_command(direction, speed)
    CarTcpClient.send_command(command)
  end

  @spec turn(integer(), integer()) :: {:ok, binary()} | {:error, term()}
  def turn(steer, speed) do
    steer = CarProtocol.clamp(steer, -100, 100)
    speed = CarProtocol.clamp(speed, 0, 255)

    if speed == 0 do
      stop()
    else
      {left_speed, right_speed} = differential_speeds(speed, steer)
      CarTcpClient.send_command(CarProtocol.motor_speed_command(left_speed, right_speed))
    end
  end

  @spec joystick(number(), number()) :: {:ok, :moved} | {:error, term()}
  def joystick(x, y) do
    vector = joystick_vector(x, y)
    execute_joystick_vector(vector)
  end

  @spec joystick_vector(number(), number()) :: joystick_vector()
  def joystick_vector(x, y) do
    x = x |> to_float() |> clamp_float(-1.0, 1.0) |> apply_deadzone()
    y = y |> to_float() |> clamp_float(-1.0, 1.0) |> apply_deadzone()
    steer_deg = quantize_steer(x)
    x_mix = steer_deg / @max_steer_deg

    left = y + x_mix
    right = y - x_mix
    scale = max(1.0, max(abs(left), abs(right)))

    left_speed =
      left
      |> Kernel./(scale)
      |> Kernel.*(255.0)
      |> round()
      |> CarProtocol.clamp(-255, 255)

    right_speed =
      right
      |> Kernel./(scale)
      |> Kernel.*(255.0)
      |> round()
      |> CarProtocol.clamp(-255, 255)

    left_speed = quantize_signed_speed(left_speed)
    right_speed = quantize_signed_speed(right_speed)

    {command, command_key} = command_from_wheel_speeds(left_speed, right_speed, steer_deg)

    %{
      x: x,
      y: y,
      steer_deg: steer_deg,
      left_speed: left_speed,
      right_speed: right_speed,
      command: command,
      command_key: command_key
    }
  end

  @spec sensor(:ultrasound | :line | {:line, :left | :middle | :right}) ::
          {:ok, term()} | {:error, term()}
  def sensor(:ultrasound) do
    with {:ok, payload} <-
           CarTcpClient.send_command(CarProtocol.ultrasound_command(),
             await_response: true,
             timeout_ms: @sensor_timeout_ms
           ) do
      {:ok, parse_sensor_payload(payload)}
    end
  end

  def sensor({:line, which}) when which in [:left, :middle, :right] do
    with {:ok, payload} <-
           CarTcpClient.send_command(CarProtocol.line_sensor_command(which),
             await_response: true,
             timeout_ms: @sensor_timeout_ms
           ) do
      {:ok, parse_sensor_payload(payload)}
    end
  end

  def sensor(:line) do
    with {:ok, left} <- sensor({:line, :left}),
         {:ok, middle} <- sensor({:line, :middle}),
         {:ok, right} <- sensor({:line, :right}) do
      {:ok, %{left: left, middle: middle, right: right}}
    end
  end

  @spec differential_speeds(integer(), integer()) :: {integer(), integer()}
  def differential_speeds(speed, steer) do
    steer_ratio = steer / 100.0
    left = speed * (1.0 + steer_ratio)
    right = speed * (1.0 - steer_ratio)
    max_component = max(1.0, max(abs(left), abs(right)))
    scale = speed / max_component

    left_speed = round(abs(left * scale)) |> CarProtocol.clamp(0, 255)
    right_speed = round(abs(right * scale)) |> CarProtocol.clamp(0, 255)

    {left_speed, right_speed}
  end

  defp parse_sensor_payload("true"), do: true
  defp parse_sensor_payload("false"), do: false

  defp parse_sensor_payload(payload) do
    case Integer.parse(payload) do
      {value, ""} -> value
      _ -> payload
    end
  end

  @spec execute_joystick_vector(joystick_vector()) :: {:ok, :moved} | {:error, term()}
  def execute_joystick_vector(%{command: command}), do: execute_joystick_command(command)

  @spec set_motor_speeds(integer(), integer()) :: {:ok, :moved} | {:error, term()}
  def set_motor_speeds(left_speed, right_speed) do
    left_speed = CarProtocol.clamp(left_speed, -255, 255)
    right_speed = CarProtocol.clamp(right_speed, -255, 255)

    {command, _key} = command_from_wheel_speeds(left_speed, right_speed, 0)
    execute_joystick_command(command)
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _rest} -> parsed
      :error -> 0.0
    end
  end

  defp clamp_float(value, min, _max) when value < min, do: min
  defp clamp_float(value, _min, max) when value > max, do: max
  defp clamp_float(value, _min, _max), do: value

  defp apply_deadzone(value) when abs(value) < @joystick_deadzone, do: 0.0
  defp apply_deadzone(value), do: value

  defp quantize_steer(x) do
    x
    |> Kernel.*(@max_steer_deg)
    |> Kernel./(@steer_step_deg)
    |> round()
    |> Kernel.*(@steer_step_deg)
    |> CarProtocol.clamp(-@max_steer_deg, @max_steer_deg)
  end

  defp quantize_signed_speed(0), do: 0

  defp quantize_signed_speed(speed) do
    sign = if speed < 0, do: -1, else: 1

    quantized_abs =
      speed
      |> abs()
      |> Kernel./(@speed_step_value)
      |> round()
      |> Kernel.*(@speed_step_value)
      |> CarProtocol.clamp(0, 255)

    sign * quantized_abs
  end

  defp execute_joystick_command(:stop) do
    with {:ok, _} <- stop(), do: {:ok, :moved}
  end

  defp execute_joystick_command({:drive, direction, speed}) do
    with {:ok, _} <- drive(direction, speed), do: {:ok, :moved}
  end

  defp execute_joystick_command({:motor_speed, left_speed, right_speed}) do
    command = CarProtocol.motor_speed_command(left_speed, right_speed)

    with {:ok, _} <- CarTcpClient.send_command(command), do: {:ok, :moved}
  end

  defp command_from_wheel_speeds(0, 0, _steer_deg), do: {:stop, :stop}

  defp command_from_wheel_speeds(left_speed, right_speed, _steer_deg)
       when left_speed >= 0 and right_speed >= 0 do
    left_speed = CarProtocol.clamp(left_speed, 0, 255)
    right_speed = CarProtocol.clamp(right_speed, 0, 255)

    {{:motor_speed, left_speed, right_speed}, {:motor_speed, left_speed, right_speed}}
  end

  defp command_from_wheel_speeds(left_speed, right_speed, steer_deg)
       when left_speed <= 0 and right_speed <= 0 do
    speed = max(abs(left_speed), abs(right_speed)) |> CarProtocol.clamp(0, 255)

    direction =
      cond do
        steer_deg >= @reverse_spin_threshold_deg -> :right
        steer_deg <= -@reverse_spin_threshold_deg -> :left
        true -> :backward
      end

    {{:drive, direction, speed}, {:drive, direction, speed}}
  end

  defp command_from_wheel_speeds(left_speed, right_speed, _steer_deg)
       when left_speed > 0 and right_speed < 0 do
    speed = max(abs(left_speed), abs(right_speed)) |> CarProtocol.clamp(0, 255)
    {{:drive, :right, speed}, {:drive, :right, speed}}
  end

  defp command_from_wheel_speeds(left_speed, right_speed, _steer_deg)
       when left_speed < 0 and right_speed > 0 do
    speed = max(abs(left_speed), abs(right_speed)) |> CarProtocol.clamp(0, 255)
    {{:drive, :left, speed}, {:drive, :left, speed}}
  end
end
