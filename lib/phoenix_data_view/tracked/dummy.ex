defmodule Phoenix.DataView.Tracked.Dummy do
  defmacro track(call) do
    module = __CALLER__.module

    req =
      case Macro.decompose_call(call) do
        {^module, _fun, _args} ->
          []

        {{:__MODULE__, _opts, nil}, _fun, _args} ->
          []

        {module, _fun, _args} ->
          quote do: require unquote(module)

        _ ->
          []
      end

      #unquote(req)

    quote do
      unquote(__MODULE__).track_stub(unquote(call))
    end
  end

  defmacro keyed(key, do: body) do
    quote do
      unquote(__MODULE__).keyed_stub(unquote(key), unquote(body))
    end
  end

  defmacro keyed(key, expr) do
    quote do
      unquote(__MODULE__).keyed_stub(unquote(key), unquote(expr))
    end
  end

  @doc false
  def keyed_stub(_key, _expr) do
    raise "unreachable"
  end

  @doc false
  def track_stub(_inner) do
    raise "unreachable"
  end

end
