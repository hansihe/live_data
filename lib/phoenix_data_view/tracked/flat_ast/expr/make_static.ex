defmodule Phoenix.DataView.Tracked.FlatAst.Expr.MakeStatic do
  defstruct key: nil, static_id: nil, slots: []

  def new(static_id, slots, key \\ nil) do
    %__MODULE__{
      static_id: static_id,
      slots: slots,
      key: key
    }
  end

end
