defmodule LiveData.Test.ClientProxy do
  alias LiveData.Test
  alias LiveData.Tracked.Apply

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @moduledoc false
  use GenServer

  defstruct [
    test_supervisor: nil,
    endpoint: nil,
    module: nil,
    caller: nil,
    router: nil,
    pid: nil,
    apply: Apply.new()
  ]

  def init(opts) do
    %{
      module: module,
      endpoint: endpoint,
      caller: {_, _} = caller,
      test_supervisor: test_supervisor
    } = opts

    state = %__MODULE__{
      caller: caller,
      test_supervisor: test_supervisor,
      endpoint: endpoint,
      module: module
    }

    start_ref = make_ref()
    state = case start_supervised_channel(state, start_ref) do
      {:ok, pid} ->
        mon_ref = Process.monitor(pid)

        receive do
          {^start_ref, {:ok, _join_reply}} ->
            Process.demonitor(mon_ref, [:flush])
            %{state | pid: pid}

          {:DOWN, ^mon_ref, _, _, reason} ->
            throw({:stop, reason, state})
        end
    end

    # TODO do initial render in mount
    state =
      receive do
        %Phoenix.Socket.Message{} = msg ->
          {:noreply, state} = handle_info(msg, state)
          state
      end

    view = %Test.View{
      module: state.module,
      pid: state.pid,
      proxy: self()
    }

    send_caller(state, {:ok, view, state.apply.rendered})

    {:ok, state}
  end

  def handle_info(
    %Phoenix.Socket.Message{
      event: "o",
      topic: _topic,
      payload: %{"o" => ops}
    },
    state
  ) do
    state = %{state |
      apply: Apply.apply(ops, state.apply)
    }

    {:noreply, state}
  end

  def handle_info({:render_sync, from}, state) do
    :ok = GenServer.reply(from, state.apply.rendered)
    {:noreply, state}
  end

  def handle_call(:render, from, state) do
    :ok = LiveData.Channel.ping(state.pid)
    send(self(), {:render_sync, from})
    {:noreply, state}
  end

  def handle_call({:push_client_event, data}, _from, state) do
    send(state.pid, %Phoenix.Socket.Message{event: "e", payload: %{"d" => data}})
    {:reply, :ok, state}
  end

  defp send_caller(%{caller: {pid, ref}} = _state, msg) do
    send(pid, {ref, msg})
  end

  defp start_supervised_channel(state, ref) do
    socket = %Phoenix.Socket{
      assigns: %{
        live_data_handler: fn _params ->
          {state.module, []}
        end,
        live_data_encoding: LiveData.Tracked.Encoding.Identity
      },
      transport_pid: self(),
      serializer: __MODULE__,
    }

    params = %{}

    from = {self(), ref}

    spec = %{
      id: make_ref(),
      start: {LiveData.Channel, :start_link, [{state.endpoint, from}]},
      restart: :temporary
    }

    with {:ok, pid} <- Supervisor.start_child(state.test_supervisor, spec) do
      send(pid, {Phoenix.Channel, params, from, socket})
      {:ok, pid}
    end
  end

  @doc """
  Encoding used by the Channel serializer.
  """
  def encode!(msg), do: msg

end
