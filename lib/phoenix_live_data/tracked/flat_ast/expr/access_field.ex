defmodule Phoenix.LiveData.Tracked.FlatAst.Expr.AccessField do
  defstruct top: nil, field: nil, location: nil

  def new(top, field, location \\ nil) do
    %__MODULE__{
      top: top,
      field: field,
      location: location
    }
  end
end
