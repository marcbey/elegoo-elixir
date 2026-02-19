defmodule ElegooElixir.CarProtocolTest do
  use ExUnit.Case, async: true

  alias ElegooElixir.CarProtocol

  test "motor_speed_command maps right motor to D1 and left motor to D2" do
    assert CarProtocol.motor_speed_command(120, 200) == %{
             "N" => 4,
             "D1" => 200,
             "D2" => 120
           }
  end

  test "servo_command uses direct angle scale and clamps to firmware range" do
    assert CarProtocol.servo_command(1, 90) == %{"N" => 5, "D1" => 1, "D2" => 90}
    assert CarProtocol.servo_command(1, 0) == %{"N" => 5, "D1" => 1, "D2" => 10}
    assert CarProtocol.servo_command(1, 200) == %{"N" => 5, "D1" => 1, "D2" => 170}
  end

  test "decode_frame handles heartbeat, ok, serial responses and raw payloads" do
    assert CarProtocol.decode_frame("{Heartbeat}") == :heartbeat
    assert CarProtocol.decode_frame("{ok}") == {:ok, "ok"}
    assert CarProtocol.decode_frame("{12_true}") == {:response, "12", "true"}
    assert CarProtocol.decode_frame("{abc_true}") == {:raw, "abc_true"}
    assert CarProtocol.decode_frame("{plain}") == {:raw, "plain"}
  end
end
