defmodule Phoenix.DataView.Tracked.FlatAst.Expr.Var do
  defstruct ref_expr: nil

  def new(ref_expr) do
    %__MODULE__{
      ref_expr: ref_expr
    }
  end
end
