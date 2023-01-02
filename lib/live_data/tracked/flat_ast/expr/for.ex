defmodule LiveData.Tracked.FlatAst.Expr.For do
  @moduledoc """
  Corresponds to `for` list comprehension in the Elixir AST. Represented as `{:for, _, specifiers}`.

  NOTE: `uniq` and `reduce` are currently not implemented, they are TODOs.
  """

  defstruct items: nil, into: nil, inner: nil, location: nil

  def new(items, into, inner, location \\ nil) do
    %__MODULE__{
      items: items,
      into: into,
      inner: inner,
      location: location
    }
  end
end
