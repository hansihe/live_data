alias LiveData.Tracked.FlatAst.Expr

defmodule LiveData.Tracked.FlatAst.Expr.Scope do
  @moduledoc """
  In many ways similar to `Expr.Block`, but with different semantics in codegen.
  Whereas `Expr.Block` corresponds 1:1 to `:__block__` in the native Elixir AST,
  this has different behaviour.

  Each expression in an `Expr.Scope` is treated as an implicit assignment. Within
  each expression in an `Expr.Scope`, any referenced other expressions are
  treated as variable accesses to those implicit assignments.

  As with normal blocks, the last value in the scope is the result.
  """

  defstruct exprs: [], location: nil

  def new(exprs, location \\ nil) do
    %__MODULE__{
      exprs: exprs,
      location: location
    }
  end
end

defimpl Expr, for: Expr.Scope do
  def transform(%Expr.Scope{exprs: exprs} = expr, acc, fun) do
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

  def location(%Expr.Scope{location: loc}) do
    loc
  end
end
