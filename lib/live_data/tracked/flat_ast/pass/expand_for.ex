defmodule LiveData.Tracked.FlatAst.Pass.ExpandFor do
  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr

  def expand_for(ast) do
    # TODO do full tree traverse using a common util?

    ast =
      ast.exprs
      |> Enum.reduce(ast, fn
        {expr_id, expr = %Expr.For{}}, ast ->
          do_expand_for(expr, expr_id, ast)

        {_expr_id, _expr}, ast ->
          ast
      end)

    ast
  end

  def rec([], acc, inner, ast) do
    FlatAst.add_expr(
      ast,
      Expr.MakeCons.new(inner, acc)
    )
  end

  def rec([{:loop, pattern, binds, body} | items], acc, inner, ast) do
    {fn_expr_id, ast} = FlatAst.add_expr(ast)

    {var_counter, ast} = FlatAst.next_id(ast)
    acc_variable_name = {:acc, var_counter, __MODULE__}

    {acc_bind, ast} = FlatAst.add_bind(ast, fn_expr_id, 0, acc_variable_name)
    {acc_pat, ast} = FlatAst.add_pattern(ast, {:bind, acc_bind})

    {new_binds, ast} = Enum.reduce(binds, {[acc_bind], ast}, fn bind, {new_binds, ast} ->
      data = FlatAst.get_bind_data(ast, bind)
      {new_bind, ast} = FlatAst.add_bind(ast, fn_expr_id, 0, data.variable)
      {[new_bind | new_binds], ast}
    end)

    {res, ast} = rec(items, acc_bind, inner, ast)

    {inner_fn, ast} = FlatAst.add_expr(
      ast,
      Expr.Fn.new(2)
      |> Expr.Fn.add_clause([pattern, acc_pat], new_binds, nil, res)
      |> Expr.Fn.finish()
    )

    FlatAst.add_expr(ast, %Expr.CallMF{
      module: Enum,
      function: :reduce,
      args: [
        body,
        acc,
        inner_fn,
      ],
    })
  end

  def rec([{:bitstring_loop, _pattern, _binds, _body} | _items], _acc, _inner, _ast) do
    raise "not implemented"
  end

  #def rec([{:filter, body} | items], acc, inner, ast) do
  #  {res, ast} = rec(items, acc, inner, ast)

  #  FlatAst.add_expr(
  #    ast,
  #    Expr.Case.new(body)
  #    |> Expr.Case.add_clause(:todo, :todo, nil, res)
  #    |> Expr.Case.add_clause(:todo, :todo, nil, acc)
  #    |> Expr.Case.finish()
  #  )
  #end

  # Map comprehension without uniq
  def do_expand_for(e = %Expr.For{uniq: false, reduce: nil, reduce_pat: nil}, expr_id, ast) do
    # Map comprehension is inplemented by recursively reducing over
    # an accumulator, then reversing it.
    # We start out with an empty accumulator.
    {empty_list, ast} = FlatAst.add_literal(ast, [])

    # Nested reduction.
    {result, ast} = rec(e.items, empty_list, e.inner, ast)

    # Reversal.
    # This replaces the `for` expression.
    ast = FlatAst.set_expr(ast, expr_id,
      Expr.CallMF.new(Enum, :reverse, [result]))

    ast
  end

  # Map comprehension with uniq
  def do_expand_for(%Expr.For{uniq: true, reduce: nil, reduce_pat: nil}, _expr_id, _ast) do
    raise "not implemented"
  end

  # Reduce comprehension
  def do_expand_for(%Expr.For{into: nil, uniq: false}, _expr_id, _ast) do
    raise "not implemented"
  end

end
