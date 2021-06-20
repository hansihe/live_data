defmodule Phoenix.LiveData.Tracked.FlatAst.Expr.MakeStatic do
  defstruct key: nil, static_id: nil, mfa: nil, slots: [], static: nil

  def new(static_id, static, slots, mfa, key \\ nil) do
    %__MODULE__{
      static_id: static_id,
      mfa: mfa,
      slots: slots,
      key: key,
      static: static
    }
  end
end
