defmodule Phoenix.DataView.Tracked.FlatAst.Expr.Scope do
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
      exprs: exprs
    }
  end
end
