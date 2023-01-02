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
