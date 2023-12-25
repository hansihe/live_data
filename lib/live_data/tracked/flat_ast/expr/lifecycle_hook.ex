alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.LifecycleHook do
  defstruct module: nil, subtrees: []

  def new(module, subtrees) do
    %__MODULE__{
      module: module,
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

    new_expr = %{
      expr |
      subtrees: new_subtrees
    }

    {new_expr, acc}
  end

end
