defmodule Phoenix.DataView.Tracked.FlatAst.Expr.Block do
  defstruct exprs: []

  def new(exprs) do
    %__MODULE__{
      exprs: exprs
    }
  end
end
