defmodule Phoenix.DataView.Tracked.Dummy do
  defmacro track(call) do
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
end
