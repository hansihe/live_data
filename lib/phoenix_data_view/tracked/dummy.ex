defmodule Phoenix.DataView.Tracked.Dummy do
  defmacro track(call) do
    call
  end

  defmacro keyed(_key, do: body) do
    body
  end

  defmacro keyed(_key, expr) do
    expr
  end
end
