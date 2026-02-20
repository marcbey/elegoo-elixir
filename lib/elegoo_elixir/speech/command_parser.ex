defmodule ElegooElixir.Speech.CommandParser do
  @moduledoc """
  Deterministic parser from voice text to canonical control intents.
  """

  @type intent ::
          %{kind: :stop}
          | %{kind: :drive, direction: :forward | :backward}
          | %{kind: :spin, direction: :left | :right}
          | %{kind: :speed_adjust, delta: integer()}
          | %{kind: :set_speed, value: integer()}
          | %{kind: :camera_center}
          | %{kind: :camera_step, direction: :left | :right}
          | %{kind: :camera_set_angle, value: integer()}
          | %{kind: :sensor, sensor: :ultrasound | :line}

  @spec parse(binary()) :: {:ok, intent()} | {:error, :empty | :unknown}
  def parse(text) when is_binary(text) do
    normalized = normalize_text(text)

    cond do
      normalized == "" ->
        {:error, :empty}

      stop_command?(normalized) ->
        {:ok, %{kind: :stop}}

      match =
          Regex.run(
            ~r/\b(?:camera|kamera)\b.*?\b(\d{2,3})\b(?:\s*(?:deg|degree|degrees|grad))?/,
            normalized
          ) ->
        angle = match |> List.last() |> String.to_integer()
        {:ok, %{kind: :camera_set_angle, value: angle}}

      String.contains?(normalized, "camera center") or
        String.contains?(normalized, "camera centre") or
        String.contains?(normalized, "camera middle") or
          String.contains?(normalized, "kamera mitte") ->
        {:ok, %{kind: :camera_center}}

      String.contains?(normalized, "camera left") or String.contains?(normalized, "kamera links") ->
        {:ok, %{kind: :camera_step, direction: :left}}

      String.contains?(normalized, "camera right") or
          String.contains?(normalized, "kamera rechts") ->
        {:ok, %{kind: :camera_step, direction: :right}}

      match = Regex.run(~r/\b(?:speed|tempo)\b\s*(\d{1,3})\b/, normalized) ->
        speed = match |> List.last() |> String.to_integer()
        {:ok, %{kind: :set_speed, value: speed}}

      String.contains?(normalized, "faster") or String.contains?(normalized, "speed up") or
          String.contains?(normalized, "schneller") ->
        {:ok, %{kind: :speed_adjust, delta: 25}}

      String.contains?(normalized, "slower") or String.contains?(normalized, "slow down") or
          String.contains?(normalized, "langsamer") ->
        {:ok, %{kind: :speed_adjust, delta: -25}}

      sensor_line_command?(normalized) ->
        {:ok, %{kind: :sensor, sensor: :line}}

      sensor_ultrasound_command?(normalized) ->
        {:ok, %{kind: :sensor, sensor: :ultrasound}}

      drive_forward_command?(normalized) ->
        {:ok, %{kind: :drive, direction: :forward}}

      drive_backward_command?(normalized) ->
        {:ok, %{kind: :drive, direction: :backward}}

      spin_left_command?(normalized) ->
        {:ok, %{kind: :spin, direction: :left}}

      spin_right_command?(normalized) ->
        {:ok, %{kind: :spin, direction: :right}}

      true ->
        {:error, :unknown}
    end
  end

  @spec intent_key(intent()) :: term()
  def intent_key(%{kind: :stop}), do: :stop
  def intent_key(%{kind: :drive, direction: direction}), do: {:drive, direction}
  def intent_key(%{kind: :spin, direction: direction}), do: {:spin, direction}
  def intent_key(%{kind: :speed_adjust, delta: delta}), do: {:speed_adjust, delta}
  def intent_key(%{kind: :set_speed, value: value}), do: {:set_speed, value}
  def intent_key(%{kind: :camera_center}), do: :camera_center
  def intent_key(%{kind: :camera_step, direction: direction}), do: {:camera_step, direction}
  def intent_key(%{kind: :camera_set_angle, value: value}), do: {:camera_set_angle, value}
  def intent_key(%{kind: :sensor, sensor: sensor}), do: {:sensor, sensor}

  @spec describe_intent(intent()) :: String.t()
  def describe_intent(%{kind: :stop}), do: "Stop"
  def describe_intent(%{kind: :drive, direction: :forward}), do: "Drive forward"
  def describe_intent(%{kind: :drive, direction: :backward}), do: "Drive backward"
  def describe_intent(%{kind: :spin, direction: :left}), do: "Spin left"
  def describe_intent(%{kind: :spin, direction: :right}), do: "Spin right"
  def describe_intent(%{kind: :speed_adjust, delta: delta}) when delta > 0, do: "Increase speed"
  def describe_intent(%{kind: :speed_adjust, delta: delta}) when delta < 0, do: "Decrease speed"
  def describe_intent(%{kind: :set_speed, value: value}), do: "Set speed to #{value}"
  def describe_intent(%{kind: :camera_center}), do: "Center camera"
  def describe_intent(%{kind: :camera_step, direction: :left}), do: "Move camera left"
  def describe_intent(%{kind: :camera_step, direction: :right}), do: "Move camera right"

  def describe_intent(%{kind: :camera_set_angle, value: value}),
    do: "Set camera angle to #{value}"

  def describe_intent(%{kind: :sensor, sensor: :ultrasound}), do: "Read ultrasound sensor"
  def describe_intent(%{kind: :sensor, sensor: :line}), do: "Read line sensor"

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> replace_umlauts()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp replace_umlauts(text) do
    text
    |> String.replace("ä", "ae")
    |> String.replace("ö", "oe")
    |> String.replace("ü", "ue")
    |> String.replace("ß", "ss")
  end

  defp stop_command?(text) do
    contains_any?(text, ["emergency stop", "stop now", "stop", "halt", "not aus", "stopp"])
  end

  defp drive_forward_command?(text) do
    contains_any?(text, ["drive forward", "forward", "go forward", "move forward", "vorwaerts"])
  end

  defp drive_backward_command?(text) do
    contains_any?(text, [
      "drive backward",
      "backward",
      "go back",
      "move back",
      "reverse",
      "rueckwaerts"
    ])
  end

  defp spin_left_command?(text) do
    contains_any?(text, ["spin left", "turn left", "rotate left", "left"])
  end

  defp spin_right_command?(text) do
    contains_any?(text, ["spin right", "turn right", "rotate right", "right"])
  end

  defp sensor_ultrasound_command?(text) do
    contains_any?(text, ["ultrasound", "distance sensor", "distance", "ultraschall"])
  end

  defp sensor_line_command?(text) do
    contains_any?(text, ["line sensor", "line sensors", "line", "liniensensor"])
  end

  defp contains_any?(text, terms) do
    Enum.any?(terms, &String.contains?(text, &1))
  end
end
