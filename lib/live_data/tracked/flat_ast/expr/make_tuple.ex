defmodule LiveData.Tracked.FlatAst.Expr.MakeTuple do
  defstruct elements: [], location: nil

  def new(elements, location \\ nil) do
    %__MODULE__{
      elements: elements,
      location: location
    }
  end
end
