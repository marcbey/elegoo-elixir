defmodule ElegooElixir.Speech.SafetyGuardTest do
  use ExUnit.Case, async: true

  alias ElegooElixir.Speech.SafetyGuard

  test "allows first command and rejects duplicate command" do
    guard = SafetyGuard.new(min_interval_ms: 250)

    assert {:ok, guard} = SafetyGuard.allow?(guard, {:drive, :forward}, now_ms: 1_000)

    assert {:skip, :duplicate, ^guard} =
             SafetyGuard.allow?(guard, {:drive, :forward}, now_ms: 1_050)

    assert {:ok, _next_guard} =
             SafetyGuard.allow?(guard, {:drive, :forward}, now_ms: 1_300)
  end

  test "rate limits different commands" do
    guard = SafetyGuard.new(min_interval_ms: 300)
    assert {:ok, guard} = SafetyGuard.allow?(guard, {:drive, :forward}, now_ms: 1_000)

    assert {:skip, :rate_limited, ^guard} =
             SafetyGuard.allow?(guard, {:drive, :backward}, now_ms: 1_200)

    assert {:ok, _next_guard} = SafetyGuard.allow?(guard, {:drive, :backward}, now_ms: 1_350)
  end

  test "bypass ignores duplicate and rate limit checks" do
    guard = SafetyGuard.new(min_interval_ms: 500)
    assert {:ok, guard} = SafetyGuard.allow?(guard, :stop, now_ms: 100)

    assert {:ok, _updated_guard} =
             SafetyGuard.allow?(guard, :stop, now_ms: 150, bypass: true)
  end
end
