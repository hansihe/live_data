defmodule LiveData.Tracked.FlatAst.Expr.MakeMap do
  defstruct prev: nil, kvs: [], location: nil

  def new(prev, kvs, location \\ nil) do
    %__MODULE__{
      prev: prev,
      kvs: kvs,
      location: location
    }
  end
end
