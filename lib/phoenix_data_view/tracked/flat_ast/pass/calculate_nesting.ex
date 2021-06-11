defmodule Phoenix.DataView.Tracked.FlatAst.Pass.CalculateNesting do
  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.FlatAst.Expr

  def calculate_nesting(ast) do
    calculate_nesting_rec(ast.root, false, [], %{}, ast)
  end

  def calculate_nesting_rec(expr_id, scoped_mode, path, acc, ast) do
    expr = FlatAst.get(ast, expr_id)

    case {scoped_mode, expr} do
      {false, _} ->
        acc = Map.put(acc, expr_id, path)
        calculate_nesting_rec(expr, expr_id, false, [expr_id | path], acc, ast)

      {0, _} ->
        acc = Map.put(acc, expr_id, path)
        calculate_nesting_rec(expr, expr_id, 1, [expr_id | path], acc, ast)

      {1, %Expr.Scope{}} ->
        acc = Map.put(acc, expr_id, path)
        calculate_nesting_rec(expr, expr_id, false, [expr_id | path], acc, ast)

      {1, _} ->
        acc
    end
  end

  def calculate_nesting_rec(expr, expr_id, scoped_mode, path, acc, ast) do
    FlatAst.Util.reduce_expr(expr, acc, fn
      :scope, _selector, expr, acc ->
        calculate_nesting_rec(expr, scoped_mode, path, acc, ast)

      :value, _selector, expr, acc ->
        calculate_nesting_rec(expr, scoped_mode, path, acc, ast)

      :literal, _, _, acc ->
        acc

      :ref, _, _, acc ->
        acc

      :pattern, _, _, acc ->
        acc
    end)
  end

  #def calculate_nesting_rec(expr_id, scoped_mode, path, acc, ast) do
  #  expr = FlatAst.get(ast, expr_id)
  #  case {scoped_mode, expr} do
  #    {false, _} ->
  #      acc = Map.put(acc, expr_id, path)
  #      calculate_nesting_rec(expr, expr_id, false, [expr_id | path], acc, ast)

  #    {0, _} ->
  #      acc = Map.put(acc, expr_id, path)
  #      calculate_nesting_rec(expr, expr_id, 1, [expr_id | path], acc, ast)

  #    {1, %Expr.Scope{}} ->
  #      acc = Map.put(acc, expr_id, path)
  #      calculate_nesting_rec(expr, expr_id, false, [expr_id | path], acc, ast)

  #    {1, _} ->
  #      acc
  #  end
  #end

  #def calculate_nesting_rec(%Expr.Fn{} = expr, expr_id, scoped_mode, path, acc, ast) do
  #  Enum.reduce(expr.clauses, acc, fn {_pattern, _binds, guard, body}, acc ->
  #    acc = if guard do
  #        calculate_nesting_rec(guard, scoped_mode, path, acc, ast)
  #      else
  #        acc
  #      end

  #    calculate_nesting_rec(body, scoped_mode, path, acc, ast)
  #  end)
  #end

  #def calculate_nesting_rec(%Expr.Scope{exprs: exprs}, expr_id, scoped_mode, path, acc, ast) do
  #  Enum.reduce(exprs, acc, fn expr, acc ->
  #    calculate_nesting_rec(expr, 0, path, acc, ast)
  #  end)
  #end

  #def calculate_nesting_rec(%Expr.For{} = expr, expr_id, scoped_mode, path, acc, ast) do
  #  acc = Enum.reduce(expr.items, acc, fn
  #    {:loop, _pat, _binds, body}, acc ->
  #      calculate_nesting_rec(body, scoped_mode, path, acc, ast)

  #    {:filter, body}, acc ->
  #      calculate_nesting_rec(body, scoped_mode, path, acc, ast)
  #  end)

  #  acc = if expr.into do
  #    calculate_nesting_rec(expr.into, scoped_mode, path, acc, ast)
  #  else
  #    acc
  #  end

  #  calculate_nesting_rec(expr.inner, scoped_mode, path, acc, ast)
  #end

  #def calculate_nesting_rec(%Expr.MakeMap{prev: nil} = expr, expr_id, scoped_mode, path, acc, ast) do
  #  Enum.reduce(expr.kvs, acc, fn {key, val}, acc ->
  #    acc = calculate_nesting_rec(key, scoped_mode, path, acc, ast)
  #    calculate_nesting_rec(val, scoped_mode, path, acc, ast)
  #  end)
  #end

  #def calculate_nesting_rec(%Expr.AccessField{top: top} = expr, expr_id, scoped_mode, path, acc, ast) do
  #  calculate_nesting_rec(top, scoped_mode, path, acc, ast)
  #end

  #def calculate_nesting_rec(%Expr.CallMF{} = expr, expr_id, scoped_mode, path, acc, ast) do
  #  acc = if expr.module do
  #    calculate_nesting_rec(expr.module, scoped_mode, path, acc, ast)
  #  else
  #    acc
  #  end

  #  acc = calculate_nesting_rec(expr.function, scoped_mode, path, acc, ast)

  #  Enum.reduce(expr.args, acc, fn arg, acc ->
  #    calculate_nesting_rec(arg, scoped_mode, path, acc, ast)
  #  end)
  #end

end
