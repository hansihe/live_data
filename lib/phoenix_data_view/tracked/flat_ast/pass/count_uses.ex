defmodule Phoenix.DataView.Tracked.FlatAst.Pass.CountUses do
  alias Phoenix.DataView.Tracked.FlatAst.Util

  def count_uses(ast) do
    Util.traverse(ast, ast.root, %{}, fn _expr_id, expr, acc ->
      acc =
        expr
        |> Util.child_exprs()
        |> Enum.filter(fn
            {:expr_bind, _eid, _selector} -> true
            _ -> false
        end)
        |> Enum.reduce(acc, fn bind, acc ->
          Map.update(acc, bind, 1, &(&1 + 1))
        end)

      {:continue, acc}
    end)
  end

end
