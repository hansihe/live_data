defmodule LiveData.Tracked.FlatAst.Pass.Normalize do
  @moduledoc false

  """
  Normalizes the AST, making things easier for later passes.

  * Flatten nested blocks into a single linear block.
  * Normalize nested expressions into a sequence of assignments. The value
    portion of an assignment is only ever one expression deep.

  Before the normalization pass is run, the AST will contain `Expr.Block`
  nodes.

  After normalization, all `Expr.Block`s will be rewritten into `Expr.Scope`s.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr

  def normalize(ast) do
    %Expr.Fn{} = expr = FlatAst.get(ast, ast.root)

    {new_clauses, ast} =
      Enum.map_reduce(expr.clauses, ast, fn %Expr.Fn.Clause{} = clause, ast ->
        {new_guard, ast} =
          if clause.guard do
            flatten_block(clause.guard, ast)
          else
            {nil, ast}
          end

        {new_body, ast} = flatten_block(clause.body, ast)

        {%{clause | guard: new_guard, body: new_body}, ast}
      end)

    ast =
      FlatAst.set_expr(ast, ast.root, %{
        expr
        | clauses: new_clauses
      })

    ast
  end

  def flatten_block(expr_id, ast) do
    {_last_item, block_items, ast} = flatten_block_rec(expr_id, ast)
    block_items = FlatAst.Util.recursive_flatten(block_items)

    # TODO filter useless

    {expr_id, ast} = FlatAst.add_expr(ast, Expr.Scope.new(block_items))
    {expr_id, ast}
  end

  def flatten_block_rec(expr_id, ast) do
    expr = FlatAst.get(ast, expr_id)
    flatten_block_rec_inner(expr, expr_id, ast)
  end

  def flatten_block_rec_inner(%Expr.Block{exprs: exprs}, _expr_id, ast) do
    {block_exprs, {last_expr, ast}} =
      Enum.map_reduce(exprs, {nil, ast}, fn expr_id, {_last, ast} ->
        {last_expr, exprs, ast} = flatten_block_rec(expr_id, ast)
        {exprs, {last_expr, ast}}
      end)

    {last_expr, ast} =
      case last_expr do
        nil ->
          FlatAst.add_literal(ast, nil)

        expr ->
          {expr, ast}
      end

    {last_expr, block_exprs, ast}
  end

  def flatten_block_rec_inner(%Expr.Var{} = expr, expr_id, ast) do
    {expr.ref_expr, [expr_id], ast}
  end

  def flatten_block_rec_inner({:literal, _lit}, lit_id, ast) do
    {lit_id, [lit_id], ast}
  end

  def flatten_block_rec_inner(expr, expr_id, ast) do
    {new_expr, {exprs, ast}} =
      FlatAst.Util.transform_expr(expr, {[], ast}, fn
        :value, _selector, sub_expr_id, {acc, ast} ->
          {val, items, ast} = flatten_block_rec(sub_expr_id, ast)
          {val, {[acc, items], ast}}

        :scope, _selector, sub_expr_id, {acc, ast} ->
          {val, ast} = flatten_block(sub_expr_id, ast)
          {val, {acc, ast}}

        :literal, _selector, lit_id, {acc, ast} ->
          {lit_id, {acc, ast}}

        :pattern, _selector, pat_id, {acc, ast} ->
          {pat_id, {acc, ast}}

        :ref, _ref, ref_id, {acc, ast} ->
          {ref_id, {acc, ast}}
      end)

    ast = FlatAst.set_expr(ast, expr_id, new_expr)

    {expr_id, [exprs, expr_id], ast}
  end
end
