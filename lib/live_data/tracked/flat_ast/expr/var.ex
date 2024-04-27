alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.Var do
  @moduledoc false

  defstruct ref_expr: nil, location: nil

  def new(ref_expr, location \\ nil) do
    %__MODULE__{
      ref_expr: ref_expr,
      location: location
    }
  end
end

defimpl Expr, for: Expr.Var do
  def transform(%Expr.Var{} = expr, acc, fun) do
    {new_ref_expr, acc} =
      case expr.ref_expr do
        {:bind, _bid} = bind ->
          fun.(:bind_ref, nil, bind, acc)
      end

    new_expr = %{expr | ref_expr: new_ref_expr}
    {new_expr, acc}
  end

  def location(%Expr.Var{location: loc}) do
    loc
  end
end
