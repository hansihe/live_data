defmodule Phoenix.DataView.Tracked.FlatAst.Expr.MakeMap do
  defstruct prev: nil, kvs: []

  def new(prev, kvs) do
    %__MODULE__{
      prev: prev,
      kvs: kvs
    }
  end
end
