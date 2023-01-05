alias LiveData.Tracked.FlatAst.Expr

defmodule LiveData.Tracked.FlatAst.Expr.Block do
  @moduledoc """
  Corresponds 1:1 with a block in the Elixir AST. Represented as a list.

  Does NOT imply a scope for variable resolution.
  """

  defstruct exprs: [], location: nil

  def new(exprs, location \\ nil) do
    %__MODULE__{
      exprs: exprs,
      location: location
    }
  end
end

defimpl Expr, for: Expr.Block do

  def transform(%Expr.Block{exprs: exprs} = expr, acc, fun) do
    num_items = Enum.count(exprs)

    {new_exprs, acc} =
      exprs
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {expr, idx}, acc ->
        fun.(:value, {idx, idx == num_items - 1}, expr, acc)
      end)

    new_expr = %{expr | exprs: new_exprs}
    {new_expr, acc}
  end

end
