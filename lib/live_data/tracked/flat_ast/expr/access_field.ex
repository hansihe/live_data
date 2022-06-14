defmodule LiveData.Tracked.FlatAst.Expr.AccessField do
  @moduledoc false

  defstruct top: nil, field: nil, location: nil

  def new(top, field, location \\ nil) do
    %__MODULE__{
      top: top,
      field: field,
      location: location
    }
  end
end
