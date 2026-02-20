defmodule ElegooElixir.Speech.SafetyGuard do
  @moduledoc """
  Guards speech command execution with rate limiting and de-duplication.
  """

  defstruct min_interval_ms: 250, last_intent_key: nil, last_executed_at_ms: nil

  @type t :: %__MODULE__{
          min_interval_ms: pos_integer(),
          last_intent_key: term() | nil,
          last_executed_at_ms: non_neg_integer() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      min_interval_ms:
        Keyword.get(opts, :min_interval_ms, speech_config(:voice_min_command_interval_ms, 250)),
      last_intent_key: nil,
      last_executed_at_ms: nil
    }
  end

  @spec allow?(t(), term(), keyword()) ::
          {:ok, t()} | {:skip, :duplicate | :rate_limited, t()}
  def allow?(%__MODULE__{} = guard, intent_key, opts \\ []) do
    now_ms = Keyword.get(opts, :now_ms, System.monotonic_time(:millisecond))
    bypass? = Keyword.get(opts, :bypass, false)

    cond do
      bypass? ->
        {:ok, remember(guard, intent_key, now_ms)}

      limited?(guard, now_ms) and same_intent?(guard, intent_key) ->
        {:skip, :duplicate, guard}

      limited?(guard, now_ms) ->
        {:skip, :rate_limited, guard}

      true ->
        {:ok, remember(guard, intent_key, now_ms)}
    end
  end

  defp same_intent?(%__MODULE__{last_intent_key: nil}, _intent_key), do: false

  defp same_intent?(%__MODULE__{last_intent_key: last_key}, intent_key),
    do: last_key == intent_key

  defp limited?(%__MODULE__{last_executed_at_ms: nil}, _now_ms), do: false

  defp limited?(%__MODULE__{min_interval_ms: min_ms, last_executed_at_ms: last_ms}, now_ms) do
    now_ms - last_ms < min_ms
  end

  defp remember(%__MODULE__{} = guard, intent_key, now_ms) do
    %{guard | last_intent_key: intent_key, last_executed_at_ms: now_ms}
  end

  defp speech_config(key, default) do
    Application.get_env(:elegoo_elixir, :speech, [])
    |> Keyword.get(key, default)
  end
end
