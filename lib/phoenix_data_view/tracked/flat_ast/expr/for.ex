defmodule Phoenix.DataView.Tracked.FlatAst.Expr.For do
  defstruct items: nil, into: nil, inner: nil

  def new(items, into, inner) do
    %__MODULE__{
      items: items,
      into: into,
      inner: inner
    }
  end
end
