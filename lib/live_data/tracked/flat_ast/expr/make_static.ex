alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.MakeStatic do
  @moduledoc false

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

defimpl Expr, for: Expr.MakeStatic do
  def transform(%Expr.MakeStatic{} = expr, acc, fun) do
    {new_slots, acc} =
      expr.slots
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {elem, idx}, acc ->
        fun.(:value, idx, elem, acc)
      end)

    new_expr = %{expr | slots: new_slots}
    {new_expr, acc}
  end

  def location(%Expr.MakeStatic{}) do
    nil
  end
end
