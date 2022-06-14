defmodule LiveData.Tracked.FlatAst.Expr.MakeMap do
  @moduledoc false

  defstruct prev: nil, kvs: [], location: nil

  def new(prev, kvs, location \\ nil) do
    %__MODULE__{
      prev: prev,
      kvs: kvs,
      location: location
    }
  end
end
