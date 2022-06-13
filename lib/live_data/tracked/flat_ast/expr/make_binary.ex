defmodule LiveData.Tracked.FlatAst.Expr.MakeBinary do
  defstruct components: [], location: nil

  def new(components, location) do
    %__MODULE__{
      components: components,
      location: location
    }
  end
end
