defmodule Phoenix.DataView.Tracked.FlatAst.Expr.AccessField do
  defstruct top: nil, field: nil

  def new(top, field) do
    %__MODULE__{
      top: top,
      field: field
    }
  end
end
