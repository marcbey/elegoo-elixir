defmodule ElegooElixir.CarTcpClient do
  @moduledoc """
  Persistent TCP client for the Elegoo car control socket.
  """

  use GenServer

  alias ElegooElixir.CarProtocol

  @topic "car:events"
  @default_reconnect_ms 1_000
  @default_cli_timeout_ms 1_500

  defmodule State do
    @moduledoc false
    defstruct [
      :host,
      :port,
      :socket,
      :reconnect_timer,
      :sequence,
      :last_seen_at,
      :last_error,
      :buffer,
      :pending,
      :reconnect_ms,
      :cli_timeout_ms
    ]
  end

  @type status :: %{
          connected: boolean(),
          host: String.t(),
          port: non_neg_integer(),
          last_seen_at: DateTime.t() | nil,
          last_error: term() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(ElegooElixir.PubSub, @topic)
  end

  @spec connect() :: :ok
  def connect, do: GenServer.cast(__MODULE__, :connect)

  @spec status() :: status()
  def status, do: GenServer.call(__MODULE__, :status)

  @spec send_command(map(), keyword()) :: {:ok, binary()} | {:error, term()}
  def send_command(command, opts \\ []) when is_map(command) do
    GenServer.call(__MODULE__, {:send_command, command, opts}, Keyword.get(opts, :timeout, 5_000))
  end

  @impl true
  def init(opts) do
    car_config = Application.get_env(:elegoo_elixir, :car, [])
    host = Keyword.get(opts, :host, Keyword.get(car_config, :host, "192.168.4.1"))
    port = Keyword.get(opts, :port, Keyword.get(car_config, :port, 100))

    reconnect_ms =
      Keyword.get(
        opts,
        :reconnect_ms,
        Keyword.get(car_config, :reconnect_ms, @default_reconnect_ms)
      )

    cli_timeout_ms =
      Keyword.get(
        opts,
        :cli_timeout_ms,
        Keyword.get(car_config, :cli_timeout_ms, @default_cli_timeout_ms)
      )

    state = %State{
      host: host,
      port: port,
      socket: nil,
      reconnect_timer: nil,
      sequence: 0,
      last_seen_at: nil,
      last_error: nil,
      buffer: "",
      pending: %{},
      reconnect_ms: reconnect_ms,
      cli_timeout_ms: cli_timeout_ms
    }

    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_cast(:connect, state) do
    {:noreply, maybe_connect(state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, build_status(state), state}
  end

  def handle_call({:send_command, _command, opts}, _from, %State{socket: nil} = state) do
    await_response? = Keyword.get(opts, :await_response, false)

    if await_response? do
      {:reply, {:error, :disconnected}, state}
    else
      {:reply, {:error, :disconnected}, state}
    end
  end

  def handle_call({:send_command, command, opts}, from, state) do
    sequence = state.sequence + 1
    serial = Integer.to_string(sequence)
    command_with_serial = Map.put_new(command, "H", serial)
    await_response? = Keyword.get(opts, :await_response, false)
    timeout_ms = Keyword.get(opts, :timeout_ms, state.cli_timeout_ms)

    with {:ok, frame} <- CarProtocol.encode_json(command_with_serial),
         :ok <- :gen_tcp.send(state.socket, frame) do
      if await_response? do
        timer_ref = Process.send_after(self(), {:pending_timeout, serial}, timeout_ms)
        pending = Map.put(state.pending, serial, {from, timer_ref})
        {:noreply, %{state | sequence: sequence, pending: pending}}
      else
        {:reply, {:ok, serial}, %{state | sequence: sequence}}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, disconnect(state, reason)}

      reason ->
        {:reply, {:error, reason}, disconnect(state, reason)}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    {:noreply, maybe_connect(%{state | reconnect_timer: nil})}
  end

  def handle_info({:pending_timeout, serial}, state) do
    case Map.pop(state.pending, serial) do
      {nil, pending} ->
        {:noreply, %{state | pending: pending}}

      {{from, _timer_ref}, pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  def handle_info({:tcp, socket, data}, %State{socket: socket} = state) do
    :ok = :inet.setopts(socket, active: :once)
    now = DateTime.utc_now()
    {frames, remainder} = extract_frames(state.buffer <> data)

    next_state =
      frames
      |> Enum.reduce(%{state | buffer: remainder, last_seen_at: now}, &handle_frame/2)

    {:noreply, next_state}
  end

  def handle_info({:tcp_closed, socket}, %State{socket: socket} = state) do
    {:noreply, disconnect(state, :tcp_closed)}
  end

  def handle_info({:tcp_error, socket, reason}, %State{socket: socket} = state) do
    {:noreply, disconnect(state, reason)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp maybe_connect(%State{socket: socket} = state) when not is_nil(socket), do: state

  defp maybe_connect(state) do
    connect_opts = [:binary, packet: :raw, active: :once, nodelay: true, send_timeout: 2_000]

    case :gen_tcp.connect(String.to_charlist(state.host), state.port, connect_opts, 2_500) do
      {:ok, socket} ->
        broadcast({:connected, %{host: state.host, port: state.port}})

        %{
          state
          | socket: socket,
            reconnect_timer: nil,
            buffer: "",
            last_seen_at: DateTime.utc_now(),
            last_error: nil
        }

      {:error, reason} ->
        broadcast({:connect_failed, reason})
        schedule_reconnect(%{state | last_error: reason})
    end
  end

  defp schedule_reconnect(%State{reconnect_timer: timer} = state) when is_reference(timer),
    do: state

  defp schedule_reconnect(state) do
    timer_ref = Process.send_after(self(), :connect, state.reconnect_ms)
    %{state | reconnect_timer: timer_ref}
  end

  defp disconnect(%State{socket: socket} = state, reason) do
    if socket, do: :gen_tcp.close(socket)

    Enum.each(state.pending, fn {_serial, {from, timer_ref}} ->
      Process.cancel_timer(timer_ref)
      GenServer.reply(from, {:error, :disconnected})
    end)

    broadcast({:disconnected, reason})

    schedule_reconnect(%{
      state
      | socket: nil,
        pending: %{},
        buffer: "",
        last_seen_at: nil,
        last_error: reason
    })
  end

  defp handle_frame(frame, state) do
    broadcast({:frame, frame})

    case CarProtocol.decode_frame(frame) do
      :heartbeat ->
        _ = :gen_tcp.send(state.socket, CarProtocol.heartbeat_frame())
        broadcast(:heartbeat)
        state

      {:response, serial, payload} ->
        case Map.pop(state.pending, serial) do
          {nil, pending} ->
            broadcast({:unmatched_response, serial, payload})
            %{state | pending: pending}

          {{from, timer_ref}, pending} ->
            Process.cancel_timer(timer_ref)
            GenServer.reply(from, {:ok, payload})
            %{state | pending: pending}
        end

      {:ok, payload} ->
        broadcast({:ok, payload})
        state

      {:raw, payload} ->
        broadcast({:raw, payload})
        state
    end
  end

  defp build_status(state) do
    %{
      connected: not is_nil(state.socket),
      host: state.host,
      port: state.port,
      last_seen_at: state.last_seen_at,
      last_error: Map.get(state, :last_error)
    }
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(ElegooElixir.PubSub, @topic, {:car_event, event})
  end

  defp extract_frames(data), do: extract_frames(data, 0, "", [])

  defp extract_frames(<<>>, 0, current, frames), do: {Enum.reverse(frames), current}
  defp extract_frames(<<>>, _depth, current, frames), do: {Enum.reverse(frames), current}

  defp extract_frames(<<char, rest::binary>>, depth, current, frames) do
    cond do
      depth == 0 and char != ?{ ->
        extract_frames(rest, depth, current, frames)

      char == ?{ ->
        extract_frames(rest, depth + 1, current <> <<char>>, frames)

      char == ?} and depth == 1 ->
        frame = current <> <<char>>
        extract_frames(rest, 0, "", [frame | frames])

      char == ?} and depth > 1 ->
        extract_frames(rest, depth - 1, current <> <<char>>, frames)

      true ->
        extract_frames(rest, depth, current <> <<char>>, frames)
    end
  end
end
