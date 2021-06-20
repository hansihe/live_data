defmodule Phoenix.LiveData.Tracked.FlatAst.Expr.Block do
  defstruct exprs: [], location: nil

  def new(exprs, location \\ nil) do
    %__MODULE__{
      exprs: exprs,
      location: location
    }
  end
end
