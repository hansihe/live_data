defmodule LiveData.Tracked.FlatAst.Expr.AccessField do
  @moduledoc """
  Corresponds to field access in the Elixir AST. Represented as `{:., _opts, [value, field]}`.
  """

  defstruct top: nil, field: nil, location: nil

  def new(top, field, location \\ nil) do
    %__MODULE__{
      top: top,
      field: field,
      location: location
    }
  end
end
