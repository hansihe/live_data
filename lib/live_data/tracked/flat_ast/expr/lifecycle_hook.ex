alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.LifecycleHook do
  defstruct module: nil, args: [], subtrees: []

  def new(module, args, [] = subtrees) do
    %__MODULE__{
      module: module,
      args: args,
      subtrees: subtrees
    }
  end
end

defimpl Expr, for: Expr.LifecycleHook do
  def transform(%Expr.LifecycleHook{} = expr, acc, fun) do
    {new_subtrees, acc} =
      expr.subtrees
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {arg, idx}, acc ->
        fun.(:value, {:subtree, idx}, arg, acc)
      end)

    {new_args, acc} =
      expr.args
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {arg, idx}, acc ->
        fun.(:value, {:arg, idx}, arg, acc)
      end)

    new_expr = %{
      expr
      | subtrees: new_subtrees,
      args: new_args
    }

    {new_expr, acc}
  end

  def location(%Expr.LifecycleHook{}) do
    nil
  end
end
