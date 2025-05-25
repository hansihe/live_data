defmodule LiveData.Tracked.FlatAst.Pass.Validate do
  alias LiveData.Tracked.FlatAst.Util

  def validate(ast) do
    Util.traverse(ast, ast.root, nil, fn
      {:literal, _lid}, _data, nil ->
        {:continue, nil}

      {:bind, _bid}, _data, nil ->
        {:continue, nil}

      {:expr, _eid}, expr, nil ->
        Util.transform_expr(expr, nil, fn
          _kind, _slot, data, _aux, nil ->
            {data, nil}
        end)

        {:continue, nil}
    end)
  end
end
