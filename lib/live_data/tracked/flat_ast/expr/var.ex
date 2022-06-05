defmodule LiveData.Tracked.FlatAst.Expr.Var do
  defstruct ref_expr: nil, location: nil

  def new(ref_expr, location \\ nil) do
    %__MODULE__{
      ref_expr: ref_expr,
      location: location
    }
  end
end
