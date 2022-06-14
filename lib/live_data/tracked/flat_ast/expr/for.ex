defmodule LiveData.Tracked.FlatAst.Expr.For do
  @moduledoc false

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
