defmodule ElegooElixir.Speech.CommandParserTest do
  use ExUnit.Case, async: true

  alias ElegooElixir.Speech.CommandParser

  test "parses english stop commands" do
    assert {:ok, %{kind: :stop}} = CommandParser.parse("emergency stop")
    assert {:ok, %{kind: :stop}} = CommandParser.parse("stop")
  end

  test "parses english drive commands" do
    assert {:ok, %{kind: :drive, direction: :forward}} = CommandParser.parse("drive forward")
    assert {:ok, %{kind: :drive, direction: :backward}} = CommandParser.parse("drive backward")
    assert {:ok, %{kind: :drive, direction: :backward}} = CommandParser.parse("reverse")
  end

  test "parses english spin commands" do
    assert {:ok, %{kind: :spin, direction: :left}} = CommandParser.parse("turn left")
    assert {:ok, %{kind: :spin, direction: :right}} = CommandParser.parse("spin right")
  end

  test "parses english camera commands" do
    assert {:ok, %{kind: :camera_center}} = CommandParser.parse("camera center")
    assert {:ok, %{kind: :camera_step, direction: :left}} = CommandParser.parse("camera left")

    assert {:ok, %{kind: :camera_set_angle, value: 120}} =
             CommandParser.parse("camera 120 degrees")
  end

  test "parses english speed commands" do
    assert {:ok, %{kind: :speed_adjust, delta: 25}} = CommandParser.parse("faster")
    assert {:ok, %{kind: :speed_adjust, delta: -25}} = CommandParser.parse("slow down")
    assert {:ok, %{kind: :set_speed, value: 160}} = CommandParser.parse("speed 160")
  end

  test "parses english sensor commands" do
    assert {:ok, %{kind: :sensor, sensor: :ultrasound}} = CommandParser.parse("read ultrasound")
    assert {:ok, %{kind: :sensor, sensor: :line}} = CommandParser.parse("line sensor")
  end

  test "returns unknown for unsupported text" do
    assert {:error, :unknown} = CommandParser.parse("please dance")
  end
end
