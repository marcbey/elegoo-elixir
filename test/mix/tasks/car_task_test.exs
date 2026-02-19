defmodule Mix.Tasks.CarTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    original_car_config = Application.get_env(:elegoo_elixir, :car, [])

    on_exit(fn ->
      Application.put_env(:elegoo_elixir, :car, original_car_config)
    end)

    :ok
  end

  test "prints usage when called without command" do
    output =
      capture_io(fn ->
        run_task([])
      end)

    assert output =~ "Usage:"
    assert output =~ "mix car turn --steer -100..100 --speed 0..255"
    assert output =~ "mix car servo [--angle 15..165 | --center]"
  end

  test "raises for invalid global options" do
    assert_raise Mix.Error, ~r/Invalid options:/, fn ->
      run_task(["--badopt"])
    end
  end

  test "raises for invalid drive direction before network interaction" do
    assert_raise Mix.Error, ~r/Invalid direction:/, fn ->
      run_task(["drive", "--direction", "sideways", "--speed", "120"])
    end
  end

  test "raises for invalid turn options" do
    assert_raise Mix.Error, ~r/Invalid turn options:/, fn ->
      run_task(["turn", "--foo", "1"])
    end
  end

  test "raises for invalid servo options" do
    assert_raise Mix.Error, ~r/Invalid servo options:/, fn ->
      run_task(["servo", "--foo", "1"])
    end
  end

  test "raises when servo angle and center are combined" do
    assert_raise Mix.Error, ~r/mutually exclusive/, fn ->
      run_task(["servo", "--center", "--angle", "120"])
    end
  end

  test "accepts valid drive options and reaches connection phase" do
    assert_raise Mix.Error, ~r/Could not connect to car within timeout/, fn ->
      run_task(["--timeout", "10", "drive", "--direction", "forward", "--speed", "120"])
    end
  end

  test "accepts valid servo angle options and reaches connection phase" do
    assert_raise Mix.Error, ~r/Could not connect to car within timeout/, fn ->
      run_task(["--timeout", "10", "servo", "--angle", "120"])
    end
  end

  test "accepts servo center options and reaches connection phase" do
    assert_raise Mix.Error, ~r/Could not connect to car within timeout/, fn ->
      run_task(["--timeout", "10", "servo", "--center"])
    end
  end

  test "status prints compact status line" do
    output =
      capture_io(fn ->
        run_task(["status"])
      end)

    assert output =~ "connected="
    assert output =~ "host="
    assert output =~ "port="
    assert output =~ "last_seen_at="
  end

  defp run_task(args) do
    Mix.Task.reenable("car")
    Mix.Task.run("car", args)
  end
end
