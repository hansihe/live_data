defmodule Phoenix.DataView.Tracked.FlatAst.Pass.Normalize do
  @moduledoc """
  Normalizes the AST, making things easier for later passes.

  * Flatten nested blocks into a single linear block.
  * Normalize nested expressions into a sequence of assignments. The value
    portion of an assignment is only ever one expression deep.
  """

  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.FlatAst.Expr

  def normalize(ast) do
    %Expr.Fn{} = expr = FlatAst.get(ast, ast.root)

    {new_clauses, ast} =
      Enum.map_reduce(expr.clauses, ast, fn {patterns, binds, guard, body}, ast ->
        {new_guard, ast} =
          if guard do
            flatten_block(guard, ast)
          else
            {guard, ast}
          end

        {new_body, ast} = flatten_block(body, ast)

        {{patterns, binds, new_guard, new_body}, ast}
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

  def flatten_block_rec_inner(%Expr.MakeMap{prev: nil, kvs: kvs}, expr_id, ast) do
    {new_kvs_m, ast} =
      Enum.map_reduce(kvs, ast, fn {key, val}, ast ->
        {new_key, key_exprs, ast} = flatten_block_rec(key, ast)
        {new_val, val_exprs, ast} = flatten_block_rec(val, ast)
        {{{new_key, new_val}, [key_exprs, val_exprs]}, ast}
      end)

    sub_exprs = Enum.map(new_kvs_m, fn {_kv, sub} -> sub end)
    new_kvs = Enum.map(new_kvs_m, fn {kv, _sub} -> kv  end)

    ast = FlatAst.set_expr(ast, expr_id, Expr.MakeMap.new(nil, new_kvs))
    {expr_id, [sub_exprs, expr_id], ast}
  end

  def flatten_block_rec_inner(%Expr.For{} = expr, expr_id, ast) do
    {items, ast} =
      Enum.map_reduce(expr.items, ast, fn
        {:loop, pattern, bindings, body}, ast ->
          {new_body, ast} = flatten_block(body, ast)
          {{:loop, pattern, bindings, new_body}, ast}

        {:filter, body}, {acc, ast} ->
          {new_body, ast} = flatten_block(body, ast)
          {{:filter, new_body}, ast}
      end)

    {into, into_exprs, ast} =
      if expr.into do
        flatten_block_rec(expr.into, ast)
      else
        {nil, [], ast}
      end

    {inner, ast} = flatten_block(expr.inner, ast)

    ast =
      FlatAst.set_expr(ast, expr_id, %Expr.For{
        items: items,
        into: into,
        inner: inner
      })

    {expr_id, [into_exprs, expr_id], ast}
  end

  def flatten_block_rec_inner(%Expr.AccessField{} = expr, expr_id, ast) do
    {top, top_exprs, ast} = flatten_block_rec(expr.top, ast)

    ast =
      FlatAst.set_expr(ast, expr_id, %{
        expr
        | top: top
      })

    {expr_id, [top_exprs, expr_id], ast}
  end

  def flatten_block_rec_inner(%Expr.CallMF{} = expr, expr_id, ast) do
    {new_module, module_exprs, ast} =
      if expr.module do
        flatten_block_rec(expr.module, ast)
      else
        {nil, [], ast}
      end

    {new_function, function_exprs, ast} = flatten_block_rec(expr.function, ast)

    {new_args_m, ast} =
      Enum.map_reduce(expr.args, ast, fn arg, ast ->
        {new_arg, arg_exprs, ast} = flatten_block_rec(arg, ast)
        {{new_arg, arg_exprs}, ast}
      end)
    new_args = Enum.map(new_args_m, fn {arg, _exprs} -> arg end)
    arg_exprs = Enum.map(new_args_m, fn {_arg, exprs} -> exprs end)

    ast =
      FlatAst.set_expr(ast, expr_id, %Expr.CallMF{
        module: new_module,
        function: new_function,
        args: new_args
      })

    {expr_id, [module_exprs, function_exprs, arg_exprs, expr_id], ast}
  end

  def flatten_block_rec_inner(%Expr.Var{} = expr, _expr_id, ast) do
    {expr.ref_expr, [], ast}
  end

  def flatten_block_rec_inner({:literal, _lit}, lit_id, ast) do
    {lit_id, [], ast}
  end

  def add_expr(ast, body) do
    {id, ast} = FlatAst.add_expr(ast)
    ast = FlatAst.set_expr(ast, id, body)
    {id, ast}
  end

  #def add_assign(ast, body) do
  #  {{:expr, eid}, ast} = add_expr(ast, %Expr.SimpleAssign{inner: body})
  #  {{:expr_bind, eid, 0}, {:expr, eid}, ast}
  #end

  def is_expr_id({:expr, _eid}) do
    true
  end

  def is_expr_id(_other) do
    false
  end
end
