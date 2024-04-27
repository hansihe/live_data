alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.Intrinsic do
  defstruct type: nil, args: [], location: nil

  @types [
    :to_string
  ]

  def new(type, args, location \\ nil) when type in @types do
    %__MODULE__{
      type: type,
      args: args,
      location: location
    }
  end
end

defimpl Expr, for: Expr.Intrinsic do
  def transform(%Expr.Intrinsic{} = expr, acc, fun) do
    {new_args, acc} =
      Enum.reduce(Enum.with_index(expr.args), {[], acc}, fn {arg, index}, {list, acc} ->
        {new, acc} = fun.(:value, {:arg, index}, arg, acc)
        {[new | list], acc}
      end)

    new_expr = %{expr | args: new_args}
    {new_expr, acc}
  end

  def location(%Expr.Intrinsic{location: loc}) do
    loc
  end
end
