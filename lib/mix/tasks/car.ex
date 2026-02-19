defmodule Mix.Tasks.Car do
  @moduledoc """
  Terminal CLI for Elegoo car control.

  Examples:
    mix car connect
    mix car status
    mix car stop
    mix car drive --direction forward --speed 120
    mix car turn --steer 40 --speed 160
    mix car sensor --type ultrasound
    mix car sensor --type line --side all
  """

  use Mix.Task

  alias ElegooElixir.Control

  @shortdoc "Control the Elegoo car over TCP"

  @impl true
  def run(args) do
    {global_opts, command_args, invalid} =
      OptionParser.parse_head(args,
        strict: [host: :string, port: :integer, timeout: :integer],
        aliases: [h: :host, p: :port]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    Application.put_env(:elegoo_elixir, :headless_cli, true)
    maybe_override_car_config(global_opts)
    Mix.Task.run("app.start")

    case command_args do
      ["connect"] ->
        ensure_connected!(timeout_ms(global_opts))
        print_status(Control.status())

      ["status"] ->
        print_status(Control.status())

      ["stop"] ->
        ensure_connected!(timeout_ms(global_opts))
        print_result(Control.stop(), "stop")

      ["drive" | rest] ->
        run_drive(rest, timeout_ms(global_opts))

      ["turn" | rest] ->
        run_turn(rest, timeout_ms(global_opts))

      ["sensor" | rest] ->
        run_sensor(rest, timeout_ms(global_opts))

      _ ->
        print_usage()
    end
  end

  defp run_drive(args, timeout_ms) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [direction: :string, speed: :integer],
        aliases: [d: :direction, s: :speed]
      )

    if invalid != [] do
      Mix.raise("Invalid drive options: #{inspect(invalid)}")
    end

    direction =
      opts
      |> Keyword.get(:direction, "forward")
      |> parse_direction!()

    speed = Keyword.get(opts, :speed, 120)

    ensure_connected!(timeout_ms)
    print_result(Control.drive(direction, speed), "drive")
  end

  defp run_turn(args, timeout_ms) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [steer: :integer, speed: :integer],
        aliases: [k: :steer, s: :speed]
      )

    if invalid != [] do
      Mix.raise("Invalid turn options: #{inspect(invalid)}")
    end

    steer = Keyword.get(opts, :steer, 0)
    speed = Keyword.get(opts, :speed, 120)

    ensure_connected!(timeout_ms)
    print_result(Control.turn(steer, speed), "turn")
  end

  defp run_sensor(args, timeout_ms) do
    {opts, _, invalid} =
      OptionParser.parse(args, strict: [type: :string, side: :string], aliases: [t: :type])

    if invalid != [] do
      Mix.raise("Invalid sensor options: #{inspect(invalid)}")
    end

    ensure_connected!(timeout_ms)

    type = Keyword.get(opts, :type, "ultrasound")

    result =
      case type do
        "ultrasound" ->
          Control.sensor(:ultrasound)

        "line" ->
          case Keyword.get(opts, :side, "all") do
            "all" -> Control.sensor(:line)
            "left" -> Control.sensor({:line, :left})
            "middle" -> Control.sensor({:line, :middle})
            "right" -> Control.sensor({:line, :right})
            side -> {:error, {:invalid_side, side}}
          end

        unknown ->
          {:error, {:invalid_type, unknown}}
      end

    print_result(result, "sensor")
  end

  defp ensure_connected!(timeout_ms) do
    if Control.status().connected do
      :ok
    else
      Control.connect()
      wait_until_connected(timeout_ms)
    end
  end

  defp wait_until_connected(remaining_ms) when remaining_ms <= 0 do
    Mix.raise("Could not connect to car within timeout")
  end

  defp wait_until_connected(remaining_ms) do
    if Control.status().connected do
      :ok
    else
      Process.sleep(100)
      wait_until_connected(remaining_ms - 100)
    end
  end

  defp print_status(status) do
    last_seen =
      case status.last_seen_at do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        _ -> "never"
      end

    Mix.shell().info(
      "connected=#{status.connected} host=#{status.host} port=#{status.port} last_seen_at=#{last_seen}"
    )

    if status[:last_error] do
      Mix.shell().info("last_error=#{inspect(status.last_error)}")
    end
  end

  defp print_result({:ok, payload}, action) do
    Mix.shell().info("#{action}: ok (#{inspect(payload)})")
  end

  defp print_result({:error, reason}, action) do
    Mix.raise("#{action}: failed (#{inspect(reason)})")
  end

  defp parse_direction!("forward"), do: :forward
  defp parse_direction!("backward"), do: :backward
  defp parse_direction!("left"), do: :left
  defp parse_direction!("right"), do: :right
  defp parse_direction!(other), do: Mix.raise("Invalid direction: #{other}")

  defp timeout_ms(opts) do
    Keyword.get(opts, :timeout, 2_000)
  end

  defp maybe_override_car_config(opts) do
    if opts[:host] || opts[:port] || opts[:timeout] do
      base = Application.get_env(:elegoo_elixir, :car, [])

      updated =
        base
        |> Keyword.put_new(:host, "192.168.4.1")
        |> Keyword.put_new(:port, 100)
        |> Keyword.put_new(:cli_timeout_ms, 1_500)
        |> maybe_put(:host, opts[:host])
        |> maybe_put(:port, opts[:port])
        |> maybe_put(:cli_timeout_ms, opts[:timeout])

      Application.put_env(:elegoo_elixir, :car, updated)
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp print_usage do
    Mix.shell().info("""
    Usage:
      mix car connect [--host HOST] [--port PORT] [--timeout MS]
      mix car status [--host HOST] [--port PORT]
      mix car stop [--host HOST] [--port PORT]
      mix car drive --direction forward|backward|left|right --speed 0..255
      mix car turn --steer -100..100 --speed 0..255
      mix car sensor --type ultrasound
      mix car sensor --type line --side all|left|middle|right
    """)
  end
end
