defmodule Phoenix.LiveData.Channel do
  @moduledoc false
  use GenServer, restart: :temporary

  require Logger

  alias Phoenix.Socket.Message
  alias Phoenix.LiveData.Socket
  alias Phoenix.LiveData.Tracked.Tree
  alias Phoenix.LiveData.Tracked.Encoding

  defstruct socket: nil,
            view: nil,
            topic: nil,
            serializer: nil,
    tracked_state: nil,
   json_encoder: nil

  def start_link({endpoint, from}) do
    IO.inspect({endpoint, from})
    hibernate_after = endpoint.config(:live_view)[:hibernate_after] || 15000
    opts = [hibernate_after: hibernate_after]
    GenServer.start_link(__MODULE__, from, opts)
  end

  @impl true
  def init({pid, _ref}) do
    {:ok, Process.monitor(pid)}
  end

  @impl true
  def handle_info({Phoenix.Channel, params, from, phx_socket}, ref) do
    IO.inspect({params, from, phx_socket})
    Process.demonitor(ref)
    mount(params, from, phx_socket)
  end

  def handle_info({:DOWN, ref, _, _, _reason}, ref) do
    {:stop, {:shutdown, :closed}, ref}
  end

  def handle_info(
        {:DOWN, _ref, _typ, transport_pid, _reason},
        %{socket: %{transport_pid: transport_pid}} = state
      ) do
    {:stop, {:shutdown, :closed}, state}
  end

  def handle_info(%Phoenix.Socket.Message{event: "e", payload: %{"d" => data}}, state) do
    {:ok, socket} = state.view.handle_event(data, state.socket)
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

  defp mount(params, from, phx_socket) do
    %{
      "r" => [route, route_params]
    } = params

    case phx_socket.handler.__data_view__(route) do
      {view_module, view_opts} ->
        mount_view(view_module, view_opts, route_params, params, from, phx_socket)

      nil ->
        GenServer.reply(from, {:error, %{reason: "no_route"}})
        {:stop, :shutdown, :no_state}
    end
  end

  defp mount_view(view_module, _view_opts, _route_params, params, from, phx_socket) do
    %Phoenix.Socket{
      endpoint: endpoint,
      transport_pid: transport_pid,
      #handler: router
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

    state = %__MODULE__{
      socket: socket,
      view: view_module,
      topic: phx_socket.topic,
      serializer: phx_socket.serializer,
      tracked_state: Tree.new(),
      json_encoder: Encoding.JSON.new()
    }

    state = maybe_call_data_view_mount!(state, params)

    :ok = GenServer.reply(from, {:ok, %{}})

    state = render_view(state)

    {:noreply, state}
  end

  defp render_view(%{tracked_state: tracked_state, json_encoder: json_encoder} = state) do
    tree = state.view.__tracked__render__(state.socket.assigns)

    {ops, tracked_state} = Tree.render(tree, tracked_state)
    {encoded_ops, json_encoder} = Encoding.JSON.format(ops, json_encoder)

    state = %{state | tracked_state: tracked_state, json_encoder: json_encoder}

    push(state, "o", %{"o" => encoded_ops})
  end

  defp maybe_call_data_view_mount!(state, params) do
    if function_exported?(state.view, :mount, 2) do
      {:ok, socket} = state.view.mount(params, state.socket)
      %{state | socket: socket}
    else
      state
    end
  end

  defp push(state, event, payload) do
    message = %Message{topic: state.topic, event: event, payload: payload}
    send(state.socket.transport_pid, state.serializer.encode!(message))
    state
  end
end
