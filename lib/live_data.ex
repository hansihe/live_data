defmodule LiveData do
  @moduledoc """
  Documentation for `LiveData`.
  """

  alias LiveData.{Socket, Tracked}

  @type rendered :: any()

  @callback mount(params :: any(), Socket.t()) :: {:ok, Socket.t()}

  @callback handle_event(event :: any(), Socket.t()) :: {:ok, Socket.t()}
  @callback handle_info(message :: any(), Socket.t()) :: {:ok, Socket.t()}

  @callback render(Socket.assigns()) :: rendered()
  @callback __tracked__render__(Socket.assigns()) :: Tracked.tree()

  @optional_callbacks mount: 2, handle_event: 2, handle_info: 2

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use LiveData.Tracked
      import LiveData
      @behaviour LiveData
    end
  end

  def assign(%Socket{assigns: assigns} = socket, key, value) do
    assigns = Map.put(assigns, key, value)
    %{socket | assigns: assigns}
  end

  def debug_prints?, do: false
end
