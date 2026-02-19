defmodule ElegooElixir.ControlTest do
  use ExUnit.Case, async: true

  alias ElegooElixir.Control

  test "joystick_vector returns stop in center and inside deadzone" do
    assert %{command: :stop, command_key: :stop, steer_deg: 0} = Control.joystick_vector(0.0, 0.0)

    assert %{command: :stop, command_key: :stop, steer_deg: 0} =
             Control.joystick_vector(0.02, 0.02)
  end

  test "joystick_vector maps forward to differential motor command" do
    assert %{
             command: {:motor_speed, 255, 255},
             command_key: {:motor_speed, 255, 255},
             steer_deg: 0
           } = Control.joystick_vector(0.0, 1.0)
  end

  test "joystick_vector maps backward to drive backward command" do
    assert %{
             command: {:drive, :backward, 255},
             command_key: {:drive, :backward, 255},
             steer_deg: 0
           } = Control.joystick_vector(0.0, -1.0)
  end

  test "joystick_vector maps pure right/left to rotate commands with clamped steer" do
    assert %{
             command: {:drive, :right, 255},
             command_key: {:drive, :right, 255},
             steer_deg: 40
           } = Control.joystick_vector(1.0, 0.0)

    assert %{
             command: {:drive, :left, 255},
             command_key: {:drive, :left, 255},
             steer_deg: -40
           } = Control.joystick_vector(-1.0, 0.0)
  end

  test "joystick_vector quantizes steer to 5 degree increments" do
    assert %{steer_deg: 5} = Control.joystick_vector(0.11, 0.0)
    assert %{steer_deg: -5} = Control.joystick_vector(-0.11, 0.0)
  end

  test "joystick_vector quantizes speed to 5 percent steps" do
    assert %{left_speed: 52, right_speed: 52, command: {:motor_speed, 52, 52}} =
             Control.joystick_vector(0.0, 0.2)
  end

  test "differential_speeds behaves correctly at extreme steering values" do
    assert Control.differential_speeds(200, 0) == {200, 200}
    assert Control.differential_speeds(200, 100) == {200, 0}
    assert Control.differential_speeds(200, -100) == {0, 200}
  end
end
