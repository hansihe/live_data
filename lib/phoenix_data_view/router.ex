defmodule Phoenix.DataView.Router do
  @moduledoc """
  Router for Phoenix DataViews.
  """

  defmacro __using__(opts) do
    quote do
      import Phoenix.DataView.Router

      Module.register_attribute(__MODULE__, :phoenix_channels, accumulate: true)
      Module.register_attribute(__MODULE__, :phoenix_data_view_routes, accumulate: true)

      # === Begin Socket
      @behaviour Phoenix.Socket
      @before_compile Phoenix.DataView.Router
      @phoenix_socket_options unquote(opts)

      @behaviour Phoenix.Socket.Transport

      @doc false
      def child_spec(opts) do
        Phoenix.Socket.__child_spec__(__MODULE__, opts, @phoenix_socket_options)
      end

      @doc false
      def connect(map), do: Phoenix.Socket.__connect__(__MODULE__, map, @phoenix_socket_options)

      @doc false
      def init(state), do: Phoenix.Socket.__init__(state)

      @doc false
      def handle_in(message, state), do: Phoenix.Socket.__in__(message, state)

      @doc false
      def handle_info(message, state), do: Phoenix.Socket.__info__(message, state)

      @doc false
      def terminate(reason, state), do: Phoenix.Socket.__terminate__(reason, state)
      # === End Socket

      @impl Phoenix.Socket
      def connect(params, %Phoenix.Socket{} = socket, connect_info) do
        {:ok, socket}
      end

      @impl Phoenix.Socket
      def id(_socket), do: nil

      defoverridable Phoenix.Socket
    end
  end

  @doc """
  Add a regular phoenix channel to the socket. See `Phoenix.Socket.channel/3`.

  The `dv:*` channels are reserved by the implementation.
  """
  defmacro channel(topic_pattern, module, opts \\ []) do
    # Tear the alias to simply store the root in the AST.
    # This will make Elixir unable to track the dependency between
    # endpoint <-> socket and avoid recompiling the endpoint
    # (alongside the whole project) whenever the socket changes.
    module = tear_alias(module)

    case topic_pattern do
      "dv:" <> _rest ->
        raise ArgumentError, "the `dv:*` topic namespace is reserved"

      _ ->
        nil
    end

    quote do
      @phoenix_channels {unquote(topic_pattern), unquote(module), unquote(opts)}
    end
  end

  # TODO add route parameter validation support
  @doc """
  Adds a route to a DataView.
  """
  defmacro data(route, module, opts \\ []) do
    module = tear_alias(module)

    quote do
      @phoenix_data_view_routes {unquote(route), unquote(module), unquote(opts)}
    end
  end

  defp tear_alias({:__aliases__, meta, [h | t]}) do
    alias = {:__aliases__, meta, [h]}

    quote do
      Module.concat([unquote(alias) | unquote(t)])
    end
  end

  defp tear_alias(other), do: other

  defmacro __before_compile__(env) do
    channels = Module.get_attribute(env.module, :phoenix_channels)
    data_views = Module.get_attribute(env.module, :phoenix_data_view_routes)

    channel_defs =
      for {topic_pattern, module, opts} <- channels do
        topic_pattern
        |> to_topic_match()
        |> defchannel(module, opts)
      end

    data_view_defs =
      for {route, module, opts} <- data_views do
        defdataview(env.module, route, module, opts)
      end

    quote do
      # All channels under "dv:*" are reserved.
      def __channel__("dv:c:" <> _rest), do: {Phoenix.DataView.Channel, []}
      def __channel__("dv:" <> _rest), do: nil
      unquote(channel_defs)
      def __channel__(_topic), do: nil

      unquote(data_view_defs)
      def __data_view__(_route), do: nil
    end
  end

  defp to_topic_match(topic_pattern) do
    case String.split(topic_pattern, "*") do
      [prefix, ""] -> quote do: <<unquote(prefix) <> _rest>>
      [bare_topic] -> bare_topic
      _ -> raise ArgumentError, "channels using splat patterns must end with *"
    end
  end

  defp defchannel(topic_match, channel_module, opts) do
    quote do
      def __channel__(unquote(topic_match)), do: unquote({channel_module, Macro.escape(opts)})
    end
  end

  defp defdataview(router_module, route, data_view_module, opts) do
    quote do
      def __data_view__(unquote(route)), do: unquote({data_view_module, Macro.escape(opts)})
    end
  end
end
