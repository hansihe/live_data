alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.Match do
  @moduledoc false

  defstruct pattern: nil, binds: nil, rhs: nil, location: nil

  def new(pattern, binds, rhs, location \\ nil) do
    %__MODULE__{
      pattern: pattern,
      binds: binds,
      rhs: rhs,
      location: location
    }
  end
end

defimpl Expr, for: Expr.Match do

  def transform(%Expr.Match{} = expr, acc, fun) do
    {new_pattern, acc} = fun.(:pattern, :lhs, expr.pattern, acc)
    {new_rhs, acc} = fun.(:value, :rhs, expr.rhs, acc)
    {new_binds, acc} = Enum.reduce(expr.binds, {[], acc}, fn bind, {list, acc} ->
      {new, acc} = fun.(:bind, nil, bind, acc)
      {[new | list], acc}
    end)
    new_expr = %{expr | pattern: new_pattern, binds: new_binds, rhs: new_rhs}
    {new_expr, acc}
  end

end
