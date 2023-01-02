defmodule LiveData.Tracked.FlatAst.Expr.MakeBinary do
  @moduledoc """
  Corresponds to binary construction in the Elixir AST. Represented as `{:<<>>, _, elems}`.
  """

  defstruct components: [], location: nil

  def new(components, location) do
    %__MODULE__{
      components: components,
      location: location
    }
  end
end
