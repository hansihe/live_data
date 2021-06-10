defmodule Phoenix.DataView.Tracked.FlatAst.FromAst do
  alias Phoenix.DataView.Tracked.FlatAst.Expr
  alias Phoenix.DataView.Tracked.FlatAst.PDAst

  def from_clauses([first_clause | _] = clauses) do
    {:ok, out} = PDAst.init()

    {_opts, args, _guard, _body} = first_clause
    num_args = Enum.count(args)

    expr_id = PDAst.add_expr(out)

    fun = Expr.Fn.new(num_args)
    scope = %{}

    fun =
      Enum.with_index(clauses)
      |> Enum.reduce(fun, fn {{_opts, args, guard, body}, clause_idx}, fun ->
        {pat_var_map, patterns} = handle_patterns(args, scope, out)

        scope =
          Enum.reduce(pat_var_map, scope, fn {idx, var}, scope ->
            {:expr, eid} = expr_id
            sub_expr_id = {:expr_bind, eid, {clause_idx, idx}}

            :ok = PDAst.add_variable(out, var, sub_expr_id)

            Map.put(scope, var, sub_expr_id)
          end)

        guard_expr =
          case guard do
            [] -> nil
          end

        {body_expr, _scope} = from_expr(body, scope, out)

        Expr.Fn.add_clause(fun, patterns, pat_var_map, guard_expr, body_expr)
      end)

    :ok = PDAst.set_expr(out, expr_id, fun)
    :ok = PDAst.set_root(out, expr_id)

    {:ok, ast} = PDAst.finish(out)
    {:ok, ast}
  end

  # def clause_body()

  def from_pattern({name, _opts, ctx} = var, binds, scope, out)
      when is_atom(name) and is_atom(ctx) do
    processed = process_var(var)
    pattern_id = PDAst.add_pattern(out, {:bind, processed})
    {[processed | binds], pattern_id}
  end

  def from_expr({:__block__, opts, body}, scope, out) do
    {exprs, _scope} =
      Enum.map_reduce(body, scope, fn item, scope ->
        from_expr(item, scope, out)
      end)

    expr_id = PDAst.add_expr(out)
    :ok = PDAst.set_expr(out, expr_id, Expr.Block.new(exprs))

    {expr_id, scope}
  end

  # def from_expr(list, scope, out) when is_list(list) do
  #  {exprs, scope} =
  #    Enum.map_reduce(list, scope, fn item, scope ->
  #      from_expr(item, scope, out)
  #    end)

  #  expr_id = PDAst.add_expr(out)
  #  :ok = PDAst.set_expr(out, expr_id, Expr.Block.new(exprs))

  #  {expr_id, scope}
  # end

  def from_expr({name, _opts, ctx} = var, scope, out) when is_atom(name) and is_atom(ctx) do
    var = process_var(var)
    ref_expr = Map.fetch!(scope, var)

    expr_id = PDAst.add_expr(out)
    :ok = PDAst.set_expr(out, expr_id, Expr.Var.new(ref_expr))

    {expr_id, scope}
  end

  def from_expr({:%{}, opts, kvs}, scope, out) do
    {kv_exprs, _scope} =
      Enum.map_reduce(kvs, scope, fn {key, value}, scope ->
        {key_expr, scope} = from_expr(key, scope, out)
        {value_expr, scope} = from_expr(value, scope, out)

        {{key_expr, value_expr}, scope}
      end)

    expr_id = PDAst.add_expr(out)
    :ok = PDAst.set_expr(out, expr_id, Expr.MakeMap.new(nil, kv_exprs))

    {expr_id, scope}
  end

  def from_expr({:for, opts, items}, scope, out) do
    outer_scope = scope

    grouped_items =
      Enum.group_by(items, fn
        [{:into, _}] -> :meta
        [{:do, _}] -> :meta
        _ -> :loop
      end)

    meta_items =
      Map.get(grouped_items, :meta, [])
      |> Enum.map(fn [kv] -> kv end)

    loop_items = Map.get(grouped_items, :loop, [])

    into = Keyword.get(meta_items, :into, nil)

    into_expr =
      if into do
        {expr_id, _scope} = from_expr(into, scope, out)
        expr_id
      end

    expr_id = PDAst.add_expr(out)

    {item_exprs, scope} =
      Enum.map_reduce(Enum.with_index(loop_items), scope, fn
        {{:<-, _opts, [pattern, expr]}, item_idx}, scope ->
          {binds_map, [pat]} = handle_patterns([pattern], scope, out)

          scope =
            Enum.reduce(binds_map, scope, fn {idx, var}, scope ->
              {:expr, eid} = expr_id
              bind_id = {:expr_bind, eid, {item_idx, idx}}

              :ok = PDAst.add_variable(out, var, bind_id)

              Map.put(scope, var, bind_id)
            end)

          {expr_id, scope} = from_expr(expr, scope, out)

          {{:loop, pat, binds_map, expr_id}, scope}

        filter, scope ->
          {expr_id, scope} = from_expr(filter, scope, out)
          {{:filter, expr_id}, scope}
      end)

    {body_expr, scope} = from_expr(Keyword.fetch!(meta_items, :do), scope, out)

    :ok = PDAst.set_expr(out, expr_id, Expr.For.new(item_exprs, into_expr, body_expr))

    {expr_id, outer_scope}
  end

  def from_expr(atom, scope, out) when is_atom(atom) do
    lit_id = PDAst.add_literal(out, atom)

    {lit_id, scope}
  end

  def from_expr({function, _opts, args}, scope, out) when is_atom(function) do
    {function_expr, scope} = from_expr(function, scope, out)

    {arg_exprs, scope} = Enum.map_reduce(args, scope, &from_expr(&1, &2, out))

    expr_id = PDAst.add_expr(out)
    :ok = PDAst.set_expr(out, expr_id, Expr.CallMF.new(nil, function_expr, arg_exprs))

    {expr_id, scope}
  end

  def from_expr({{:., _opts1, [module, function]}, _opts2, args}, scope, out)
      when is_atom(module) and is_atom(function) do
    {module_expr, scope} = from_expr(module, scope, out)
    {function_expr, scope} = from_expr(function, scope, out)

    {arg_exprs, scope} = Enum.map_reduce(args, scope, &from_expr(&1, &2, out))

    expr_id = PDAst.add_expr(out)
    :ok = PDAst.set_expr(out, expr_id, Expr.CallMF.new(module_expr, function_expr, arg_exprs))

    {expr_id, scope}
  end

  def from_expr({{:., _opts1, [top, field]}, _opts2, args}, scope, out) when is_atom(field) do
    {top_expr, scope} = from_expr(top, scope, out)

    expr_id = PDAst.add_expr(out)
    :ok = PDAst.set_expr(out, expr_id, Expr.AccessField.new(top_expr, field))

    {expr_id, scope}
  end

  def handle_patterns(patterns, scope, out) do
    args_pats = Enum.map(patterns, &from_pattern(&1, [], scope, out))
    patterns = Enum.map(args_pats, fn {_binds, pat} -> pat end)

    {_idx, pat_var_map} =
      args_pats
      |> Enum.map(fn {binds, _pat} -> binds end)
      |> Enum.concat()
      |> Enum.reduce({0, %{}}, fn
        bind, {idx, map} when is_map_key(map, bind) ->
          {idx, map}

        bind, {idx, map} ->
          map = Map.put(map, idx, bind)
          {idx + 1, map}
      end)

    {pat_var_map, patterns}
  end

  def from_expr(expr, scope, out) do
    IO.inspect(expr)
    true = false
  end

  defp process_var({name, opts, ctx}) when is_atom(name) and is_atom(ctx) do
    counter = Keyword.get(opts, :counter)
    {name, counter, ctx}
  end
end
