defmodule LiveData.Tracked.FlatAst.Pass.CalculateNesting do
  @moduledoc """
  Given a FlatAST, will calculate a map of `expr_id` to a list of `expr_id`s it's
  nested within.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr

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

  def calculate_nesting_rec(expr, _expr_id, scoped_mode, path, acc, ast) do
    FlatAst.Util.reduce_expr(expr, acc, fn
      :scope, _selector, expr, acc ->
        calculate_nesting_rec(expr, scoped_mode, path, acc, ast)

      :value, _selector, expr, acc ->
        calculate_nesting_rec(expr, scoped_mode, path, acc, ast)

      :literal, _, _, acc ->
        acc

      :bind, _, _, acc ->
        acc

      :bind_ref, _, _, acc ->
        acc

      :pattern, _, _, acc ->
        acc
    end)
  end

end
