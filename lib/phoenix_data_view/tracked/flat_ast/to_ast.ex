defmodule Phoenix.DataView.Tracked.FlatAst.ToAst do
  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.FlatAst.Expr

  def to_expr(ast, opts \\ []) do
    opts = %{
      pretty: Keyword.get(opts, :pretty, false)
    }

    generated_bindings = %{}
    {expr, _gen} = to_expr(ast.root, generated_bindings, ast, false, opts)
    expr
  end

  def to_expr(expr_id, gen, ast, false, opts) do
    item = FlatAst.get(ast, expr_id)
    to_expr_inner(item, expr_id, gen, ast, false, opts)
  end

  def to_expr({:expr, _eid} = expr_id, gen, ast, true, opts) do
    case Map.fetch(gen, expr_id) do
      {:ok, var} ->
        var_ast = var_to_expr(var, gen)
        {var_ast, gen}

      :error ->
        item = FlatAst.get(ast, expr_id)
        {item_ast, gen} = to_expr_inner(item, expr_id, gen, ast, true, opts)

        unique_var = make_unique_var(opts)
        gen = Map.put(gen, expr_id, unique_var)

        {{:=, [], [var_to_expr(unique_var, gen), item_ast]}, gen}
    end
  end

  def to_expr(expr_id, gen, ast, true, opts) do
    item = FlatAst.get(ast, expr_id)
    to_expr_inner(item, expr_id, gen, ast, true, opts)
  end

  def to_expr_inner({:expr_bind, _eid, _selector} = bind, _expr_id, gen, ast, scope_mode, opts) do
    var = Map.get(ast.variables, bind) || Map.fetch!(gen, bind)
    var_ast = var_to_expr(var, gen)
    {var_ast, gen}
  end

  def to_expr_inner({:literal, literal}, _expr_id, gen, ast, scope_mode, opts) do
    {literal, gen}
  end

  def to_expr_inner(%Expr.Fn{} = expr, expr_id, gen, ast, scope_mode, opts) do
    {clauses, gen} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(gen, fn {{pattern_ids, pattern_bind_map, guard_id, body_id}, clause_idx},
                                            gen ->
        {:expr, eid} = expr_id

        {patterns_ast, gen} =
          Enum.map_reduce(pattern_ids, gen, fn pattern_id, gen ->
            to_pattern(pattern_id, gen, ast, opts)
          end)

        gen = Enum.reduce(pattern_bind_map, gen, fn {idx, var}, gen ->
          sub = {:expr_bind, eid, {clause_idx, idx}}
          Map.put(gen, sub, var)
        end)

        nil = guard_id

        {body_ast, gen} = to_expr(body_id, gen, ast, scope_mode, opts)

        {{:->, [], [patterns_ast, body_ast]}, gen}
      end)

    {{:fn, [], clauses}, gen}
  end

  def to_expr_inner(%Expr.SimpleAssign{inner: inner}, {:expr, eid}, gen, ast, scope_mode, opts) do
    {inner_ast, gen} = to_expr(inner, gen, ast, scope_mode, opts)

    unique_var = make_unique_var(opts)
    gen = Map.put(gen, {:expr_bind, eid, 0}, unique_var)

    {{:=, [], [var_to_expr(unique_var, gen), inner_ast]}, gen}
  end

  def to_expr_inner(%Expr.Block{exprs: exprs}, _expr_id, gen, ast, _scope_mode, opts) do
    {inner, gen} = Enum.map_reduce(exprs, gen, &to_expr(&1, &2, ast, false, opts))
    {{:__block__, [], inner}, gen}
  end

  def to_expr_inner(%Expr.Scope{exprs: exprs}, _expr_id, gen, ast, _scope_mode, opts) do
    {inner, gen} = Enum.map_reduce(exprs, gen, &to_expr(&1, &2, ast, true, opts))
    {{:__block__, [], inner}, gen}
  end

  def to_expr_inner(%Expr.MakeMap{prev: nil, kvs: kvs}, _expr_id, gen, ast, scope_mode, opts) do
    {kvs_ast, gen} =
      Enum.map_reduce(kvs, gen, fn {key, value}, gen ->
        {key_ast, gen} = to_expr(key, gen, ast, scope_mode, opts)
        {value_ast, gen} = to_expr(value, gen, ast, scope_mode, opts)
        {{key_ast, value_ast}, gen}
      end)

    {{:%{}, [], kvs_ast}, gen}
  end

  def to_expr_inner(%Expr.For{} = expr, {:expr, eid}, gen, ast, scope_mode, opts) do
    nil = expr.into

    {items, gen} =
      expr.items
      |> Enum.with_index()
      |> Enum.map_reduce(gen, fn
        {{:loop, pattern_id, binds_map, expr_id}, item_idx}, gen ->
          {pattern_ast, gen} = to_pattern(pattern_id, gen, ast, opts)

          gen = Enum.reduce(binds_map, gen, fn {idx, var}, gen ->
            sub = {:expr_bind, eid, {item_idx, idx}}
            Map.put(gen, sub, var)
          end)

          {expr_ast, gen} = to_expr(expr_id, gen, ast, scope_mode, opts)
          {{:<-, [], [pattern_ast, expr_ast]}, gen}

        {:filter, expr_id}, gen ->
          to_expr(expr_id, gen, ast, scope_mode, opts)
      end)

    {body_ast, gen} = to_expr(expr.inner, gen, ast, scope_mode, opts)

    {{:for, [], Enum.concat([items, [[do: body_ast]]])}, gen}
  end

  def to_expr_inner(%Expr.AccessField{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {top_expr, gen} = to_expr(expr.top, gen, ast, scope_mode, opts)
    field = expr.field

    {{{:., [], [top_expr, field]}, [no_parens: true], []}, gen}
  end

  def to_expr_inner(%Expr.Var{ref_expr: ref_expr}, _expr_id, gen, ast, scope_mode, opts) do
    var = Map.fetch!(ast.variables, ref_expr)
    var_ast = var_to_expr(var, gen)
    {var_ast, gen}
  end

  def to_expr_inner(%Expr.CallMF{module: nil} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {function_ast, gen} = to_expr(expr.function, gen, ast, scope_mode, opts)

    {args_ast, gen} = Enum.map_reduce(expr.args, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    {{function_ast, [], args_ast}, gen}
  end

  def to_expr_inner(%Expr.CallMF{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {module_ast, gen} = to_expr(expr.module, gen, ast, scope_mode, opts)
    {function_ast, gen} = to_expr(expr.function, gen, ast, scope_mode, opts)

    {args_ast, gen} = Enum.map_reduce(expr.args, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    {{{:., [], [module_ast, function_ast]}, [], args_ast}, gen}
  end

  def to_expr_inner(%Expr.MakeStatic{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {slots, gen} = Enum.map_reduce(expr.slots, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    {key, gen} =
      if expr.key do
        {key_ast, gen} = to_expr(expr.key, gen, ast, scope_mode, opts)
        key_ast = quote do
          {:ok, unquote(key_ast)}
        end

        {key_ast, gen}
      else
        {nil, gen}
      end

    expr =
      quote do
        %Phoenix.DataView.Tracked.Tree.Static{
          id: unquote(expr.static_id),
          slots: fn -> unquote(slots) end,
          key: unquote(key)
        }
      end

    {expr, gen}
  end

  def to_pattern(pattern_id, gen, ast, opts) do
    pattern = FlatAst.get(ast, pattern_id)
    to_pattern_inner(pattern, pattern_id, gen, ast, opts)
  end

  def to_pattern_inner({:bind, var}, _pattern_id, gen, _ast, _opts) do
    {var_to_expr(var, gen), gen}
  end

  def var_to_expr({name, nil, ctx}, _gen) do
    {name, [], ctx}
  end

  def var_to_expr({name, counter, ctx}, _gen) do
    {name, [counter: counter], ctx}
  end

  def make_unique_var(opts) do
    if opts.pretty do
      counter = :erlang.unique_integer([:positive])
      name = String.to_atom("gen_var_#{counter}")
      {name, counter, nil}
    else
      counter = :erlang.unique_integer([])
      {:gen_var, counter, nil}
    end
  end
end
