alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.CallValue do
  defstruct value: nil, args: [], location: nil

  def new(value, args, location \\ nil) do
    %__MODULE__{
      value: value,
      args: args,
      location: location
    }
  end
end

defimpl Expr, for: Expr.CallValue do

  def transform(%Expr.CallValue{} = expr, acc, fun) do
    {new_value, acc} = fun.(:value, :fun, expr.value, acc)

    {new_args, acc} =
      expr.args
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {arg, idx}, acc ->
        fun.(:value, {:arg, idx}, arg, acc)
      end)

    new_expr = %{
      expr |
      value: new_value,
      args: new_args
    }

    {new_expr, acc}
  end

end
