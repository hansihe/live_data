defmodule Phoenix.DataView do
  @moduledoc """
  Documentation for `Phoenix.DataView`.
  """

  alias Phoenix.DataView.{Socket, Tracked}

  @type rendered :: any()

  @callback mount(params :: any(), Socket.t()) :: {:ok, Socket.t()}

  @callback handle_event(event :: any(), Socket.t()) :: {:ok, Socket.t()}
  @callback handle_info(message :: any(), Socket.t()) :: {:ok, Socket.t()}

  @callback __tracked_render__(Socket.assigns()) :: Tracked.tree()
  @callback render(Socket.assigns()) :: rendered()

  @optional_callbacks mount: 2, handle_event: 2, handle_info: 2

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use Phoenix.DataView.Tracked
      import Phoenix.DataView
      @behaviour Phoenix.DataView
    end
  end

  def assign(%Socket{assigns: assigns} = socket, key, value) do
    assigns = Map.put(assigns, key, value)
    %{socket | assigns: assigns}
  end
end
