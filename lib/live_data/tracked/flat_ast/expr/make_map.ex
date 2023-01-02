defmodule LiveData.Tracked.FlatAst.Expr.MakeMap do
  @moduledoc """
  Corresponds to map creation, `%{}`, in the Elixir AST. Represented as `{:%{}, _, inner}`.
  """

  defstruct struct: nil, prev: nil, kvs: [], location: nil

  def new(struct, prev, kvs, location \\ nil) do
    %__MODULE__{
      struct: struct,
      prev: prev,
      kvs: kvs,
      location: location
    }
  end
end
