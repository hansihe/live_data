defmodule LiveData.Channel do
  @moduledoc false

  @prefix :live_data

  use GenServer, restart: :temporary

  require Logger

  alias Phoenix.Socket.Message
  alias LiveData.{Socket, Async}
  alias LiveData.Tracked.RenderDiff
  alias LiveData.Tracked.Encoding

  def ping(pid) do
    GenServer.call(pid, {@prefix, :ping})
  end

  defstruct socket: nil,
            view: nil,
            topic: nil,
            serializer: nil,
            tracked_state: nil,
            encoding_module: nil,
            encoding_state: nil

  def start_link({endpoint, from}) do
    if LiveData.debug_prints?(), do: IO.inspect({endpoint, from})
    hibernate_after = endpoint.config(:live_data)[:hibernate_after] || 15000
    opts = [hibernate_after: hibernate_after]
    GenServer.start_link(__MODULE__, from, opts)
  end

  @impl true
  def init({pid, _ref}) do
    {:ok, Process.monitor(pid)}
  end

  @impl true
  def handle_call({@prefix, :ping}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({Phoenix.Channel, params, from, phx_socket}, ref) do
    if LiveData.debug_prints?(), do: IO.inspect({params, from, phx_socket})
    Process.demonitor(ref)

    mount(params, from, phx_socket)
  end

  # @impl true
  # def handle_call(msg, _from, socket) do
  #  IO.inspect(msg)
  #  true = false
  # end

  # def handle_info({:DOWN, ref, _, _, _reason}, ref) do
  #  {:stop, {:shutdown, :closed}, ref}
  # end

  def handle_info(
        {:DOWN, _ref, _typ, transport_pid, _reason},
        %{socket: %{transport_pid: transport_pid}} = state
      ) do
    {:stop, {:shutdown, :closed}, state}
  end

  def handle_info(%Message{event: "e", payload: %{"d" => data}}, state) do
    {:ok, socket} = state.view.handle_event(data, state.socket)
    state = %{state | socket: socket}
    state = render_view(state)
    {:noreply, state}
  end

  def handle_info({@prefix, :async_result, {kind, info}}, state) do
    {ref, _cid, keys, result} = info
    socket = Async.handle_async(state.socket, nil, kind, keys, ref, result)
    state = %{state | socket: socket}
    state = render_view(state)
    {:noreply, state}
  end

  def handle_info(message, state) do
    {:ok, socket} = state.view.handle_info(message, state.socket)
    state = %{state | socket: socket}
    state = render_view(state)
    {:noreply, state}
  end

  defp call_handler({module, function}, params) do
    apply(module, function, [params])
  end

  defp call_handler(fun, params) when is_function(fun, 1) do
    fun.(params)
  end

  defp mount(params, from, phx_socket) do
    handler = phx_socket.assigns.live_data_handler

    case call_handler(handler, params) do
      {view_module, view_opts} ->
        mount_view(view_module, view_opts, params, from, phx_socket)

      nil ->
        GenServer.reply(from, {:error, %{reason: "no_route"}})
        {:stop, :shutdown, :no_state}
    end
  end

  defp mount_view(view_module, _view_opts, params, from, phx_socket) do
    %Phoenix.Socket{
      endpoint: endpoint,
      transport_pid: transport_pid
      # handler: router
    } = phx_socket

    Process.monitor(transport_pid)

    case params do
      %{"caller" => {pid, _}} when is_pid(pid) -> Process.put(:"$callers", [pid])
      _ -> Process.put(:"$callers", [transport_pid])
    end

    socket = %Socket{
      endpoint: endpoint,
      transport_pid: transport_pid
    }

    encoding_module = Map.get(phx_socket.assigns, :live_data_encoding, Encoding.JSON)

    state = %__MODULE__{
      socket: socket,
      view: view_module,
      topic: phx_socket.topic,
      serializer: phx_socket.serializer,
      tracked_state: RenderDiff.new(),
      encoding_module: encoding_module,
      encoding_state: encoding_module.new()
    }

    state = maybe_call_data_view_mount!(state, params)

    :ok = GenServer.reply(from, {:ok, %{}})

    state = render_view(state)

    {:noreply, state}
  end

  defp render_view(%{tracked_state: tracked_state} = state) do
    tree = state.view.__tracked__render__(state.socket.assigns)

    {ops, tracked_state} = RenderDiff.render(tree, tracked_state)
    {encoded_ops, encoding_state} = state.encoding_module.format(ops, state.encoding_state)

    state = %{state | tracked_state: tracked_state, encoding_state: encoding_state}

    if LiveData.debug_prints?(), do: IO.inspect(encoded_ops)
    state = push(state, "o", %{"o" => encoded_ops})
    state
  end

  defp maybe_call_data_view_mount!(state, params) do
    if is_exported?(state.view, :mount, 2) do
      {:ok, socket} = state.view.mount(params, state.socket)
      %{state | socket: socket}
    else
      state
    end
  end

  def report_async_result(monitor_ref, kind, ref, cid, keys, result)
      when is_reference(monitor_ref) and kind in [:assign, :start] and is_reference(ref) do
    send(monitor_ref, {@prefix, :async_result, {kind, {ref, cid, keys, result}}})
  end

  defp push(state, event, payload) do
    message = %Message{topic: state.topic, event: event, payload: payload}
    send(state.socket.transport_pid, state.serializer.encode!(message))
    state
  end

  defp is_exported?(module, function, arity) do
    case :erlang.module_loaded(module) do
      true -> nil
      false -> :code.ensure_loaded(module)
    end

    function_exported?(module, function, arity)
  end
end
