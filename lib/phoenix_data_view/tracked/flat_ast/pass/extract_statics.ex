defmodule Phoenix.DataView.Tracked.FlatAst.Pass.ExtractStatic do
  @moduledoc """
  This pass rewrites the entire AST, starting from the result of a function.
  It expects a normalized AST as an input, as defined by Pass.Normalize.

  It will traverse and rewrite the AST within one of two different modes:
  * Return value rewriting. This will perform recursive rewriting of the
    functions return value.
  * Dependent value transcription. Every scope involved in the return value is
    visited, and any missing dependent values are transcribed from the original
    AST.

  Of these two modes, return value rewriting is the one we are most interested
  in here.

  Return value rewriting is a mutually recursive function:
  * Traversal. This can traverse scopes inwards.
  * Extraction. This can only traverse within a scope, or outwards.


  """
  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.FlatAst.Expr

  def extract_static(ast, uses_count, scopes) do
    {statics, ast} = FlatAst.with_aux(ast, %{uses_count: uses_count}, fn ast ->
      {new_root, statics, _next_id, ast} = do_traverse(ast.root, %{}, 0, ast)
      ast = FlatAst.set_root(ast, new_root)
      {statics, ast}
    end)

    IO.inspect statics

    {ast, statics}
  end

  # traverse
  # traverse_inner
  # extract
  # extract_rec
  # extract_rec_inner

  def do_traverse(expr_id, statics, next_id, ast) do
    expr = FlatAst.get(ast, expr_id)
    do_traverse_inner(expr, expr_id, statics, next_id, ast)
  end

  def do_traverse_inner(%Expr.Fn{} = expr, expr_id, statics, next_id, ast) do
    {clauses, {statics, next_id, ast}} =
      Enum.map_reduce(expr.clauses, {statics, next_id, ast}, fn {patterns, binds, guard, body_id},
                                                            {statics, next_id, ast} ->
        {new_body, statics, next_id, ast} = do_traverse(body_id, statics, next_id, ast)
        {{patterns, binds, guard, new_body}, {statics, next_id, ast}}
      end)

    ast = FlatAst.set_expr(ast, expr_id, %{expr | clauses: clauses})

    {expr_id, statics, next_id, ast}
  end

  def do_traverse_inner(%Expr.Block{}, expr_id, statics, next_id, ast) do
    do_extract(expr_id, statics, next_id, ast)
  end

  def do_traverse_inner(%Expr.For{} = expr, expr_id, statics, next_id, ast) do
    {new_inner, statics, next_id, ast} = do_extract(expr.inner, statics, next_id, ast)
    ast = FlatAst.set_expr(ast, expr_id, %{expr | inner: new_inner})
    {expr_id, statics, next_id, ast}
  end

  def do_extract(expr_id, statics, next_id, ast, key_expr \\ nil) do
    {static, {_next_slot, slots}, statics, next_id, ast} = do_extract_rec(expr_id, {0, []}, statics, next_id, ast)
    slots = Enum.reverse(slots)

    data = %{
      static: static
    }
    statics = Map.put(statics, next_id, data)

    {slots_assigns, slots_vars, ast} = Enum.reduce(slots, {[], [], ast}, fn
      slot, {slot_assigns, slot_vars, ast} ->
        {id, ast} = FlatAst.add_expr(ast)
        ast = FlatAst.set_expr(ast, id, Expr.SimpleAssign.new(slot))

        {:expr, eid} = id
        bind_id = {:expr_bind, eid, 0}

        {[id | slot_assigns], [bind_id | slot_vars], ast}
    end)

    {id, ast} = FlatAst.add_expr(ast)
    ast = FlatAst.set_expr(ast, id, Expr.MakeStatic.new(next_id, Enum.reverse(slots_vars), key_expr))

    body = [expr_id] ++ Enum.reverse(slots_assigns) ++ [id]

    {outer_id, ast} = FlatAst.add_expr(ast)
    ast = FlatAst.set_expr(ast, outer_id, Expr.Block.new(body))

    {outer_id, statics, next_id + 1, ast}
  end

  def do_extract_rec(expr_id, current, statics, next_id, ast) do
    expr = FlatAst.get(ast, expr_id)
    do_extract_rec_inner(expr, expr_id, current, statics, next_id, ast)
  end

  def do_extract_rec_inner(%Expr.Block{} = block, _expr_id, current, statics, next_id, ast) do
    result_expr = List.last(block.exprs)
    do_extract_rec(result_expr, current, statics, next_id, ast)
  end

  def do_extract_rec_inner(%Expr.MakeMap{prev: nil} = expr, _expr_id, current, statics, next_id, ast) do
    {kvs, {current, statics, next_id, ast}} =
      Enum.map_reduce(expr.kvs, {current, statics, next_id, ast}, fn {key, val}, {current, statics, next_id, ast} ->
        {key_res, current, statics, next_id, ast} = do_extract_rec(key, current, statics, next_id, ast)
        {val_res, current, statics, next_id, ast} = do_extract_rec(val, current, statics, next_id, ast)
        {{key_res, val_res}, {current, statics, next_id, ast}}
      end)

    {{:map, kvs}, current, statics, next_id, ast}
  end

  def do_extract_rec_inner(%Expr.For{}, expr_id, current, statics, next_id, ast) do
    {new_expr_id, statics, next_id, ast} = do_traverse(expr_id, statics, next_id, ast)
    {slot_id, current} = add_slot(new_expr_id, current)
    {{:slot, slot_id}, current, statics, next_id, ast}
  end

  def do_extract_rec_inner(%Expr.CallMF{} = expr, expr_id, current, statics, next_id, ast) do
    case {FlatAst.get(ast, expr.module), FlatAst.get(ast, expr.function)} do
      {{:literal, Phoenix.DataView.Tracked.Dummy}, {:literal, :keyed_stub}} ->
        [key, inner] = expr.args

        {new_inner, statics, next_id, ast} = do_extract(inner, statics, next_id, ast, key)
        {slot_id, current} = add_slot(new_inner, current)

        {{:slot, slot_id}, current, statics, next_id, ast}

      {{:literal, Phoenix.DataView.Tracked.Dummy}, {:literal, :track_stub}} ->
        [inner] = expr.args
        do_tracked(inner, current, statics, next_id, ast)

      a ->
        IO.inspect(a)
        true = false
    end
  end

  def do_extract_rec_inner(%Expr.AccessField{} = _expr, expr_id, current, statics, next_id, ast) do
    {slot_id, current} = add_slot(expr_id, current)
    {{:slot, slot_id}, current, statics, next_id, ast}
  end

  def do_extract_rec_inner(%Expr.SimpleAssign{inner: inner}, _expr_id, current, statics, next_id, ast) do
    do_extract_rec(inner, current, statics, next_id, ast)
  end

  def do_extract_rec_inner({:literal, literal}, _expr_id, current, statics, next_id, ast) do
    {{:literal, literal}, current, statics, next_id, ast}
  end

  def do_extract_rec_inner({:expr_bind, eid, selector}, _expr_id, current, statics, next_id, ast) do
    inner_expr_id = {:expr, eid}
    inner_expr = FlatAst.get(ast, inner_expr_id)

    num_uses = Map.get(ast.aux.uses_count, inner_expr_id, 0)

    case inner_expr do
      %Expr.SimpleAssign{inner: inner} ->
        0 = selector
        {static, current, statics, next_id, ast} = do_extract_rec(inner, current, statics, next_id, ast)

        #if num_uses <= 1 do
        #else
        #end

        {static, current, statics, next_id, ast}
    end
  end

  def do_extract_rec_inner(expr, _expr_id, current, statics, next_id, ast) do
    IO.inspect(expr)
    true = false
  end

  def do_tracked(expr_id, current, statics, next_id, ast) do
    {expr_id, ast} = resolve(expr_id, ast)
    expr = FlatAst.get(ast, expr_id)

    do_tracked(expr, expr_id, current, statics, next_id, ast)
  end

  def do_tracked(%Expr.CallMF{} = expr, _expr_id, current, statics, next_id, ast) do
    [inner] = expr.args
    {slot_id, current} = add_slot(inner, current)
    {{:slot, slot_id}, current, statics, next_id, ast}
  end

  def resolve({:expr, _eid} = expr, ast) do
    {expr, ast}
  end

  def resolve({:expr_bind, eid, selector} = bind, ast) do
    expr_id = {:expr, eid}
    case FlatAst.get(ast, expr_id) do
      %Expr.SimpleAssign{inner: inner} ->
        0 = selector
        resolve(inner, ast)

      %Expr.For{} = expr ->
        # {item_num, bind_num} = selector
        # {:loop, _pattern, binds, _inner} = Enum.at(expr.items, item_num)
        # var =
        {bind, ast}
    end
  end

  def resolve({:literal, _lid} = literal, ast) do
    {literal, ast}
  end

  def get_atom(nil, _ast) do
    nil
  end

  def get_atom(expr_id, ast) do
    case FlatAst.get(ast, expr_id) do
      %Expr.Literal{literal: atom} when is_atom(atom) -> {:ok, atom}
      _ -> :error
    end
  end

  defp add_slot(new, {next_id, slots}) do
    {next_id, {next_id + 1, [new | slots]}}
  end

  # def do_extract(expr_id, statics, next_id, ast) do
  #  expr = FlatAst.get(ast, expr_id)
  #  do_extract_inner(expr, expr_id, statics, next_id, ast)
  # end

  # def do_extract_inner(%Expr.Fn{} = expr, expr_id, statics, next_id, ast) do

  #  true = false
  # end

  # def do_extract_inner(%Expr.Block{} = expr, expr_id, statics, next_id, ast) do
  #  true = false
  # end
end
