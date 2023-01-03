defmodule LiveData.Tracked.FlatAst.FromAst do
  @moduledoc """
  Module which converts a regular Elixir AST to a FlatAst.
  """

  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FlatAst.PDAst

  defp norm_items(items) do
    Enum.reverse(norm_items_rec(items, []))
  end

  defp norm_items_rec([[_ | _] = inner | tail], acc) do
    acc = norm_items_rec(inner, acc)
    norm_items_rec(tail, acc)
  end
  defp norm_items_rec([head | tail], acc) do
    norm_items_rec(tail, [head | acc])
  end
  defp norm_items_rec([], acc) do
    acc
  end

  def from_clauses([first_clause | _] = clauses) do
    {:ok, out} = PDAst.init()

    {first_clause_opts, args, _guard, _body} = first_clause
    num_args = Enum.count(args)

    first_clause_location = make_location(first_clause_opts)

    expr_id = PDAst.add_expr(out)

    fun = Expr.Fn.new(num_args, first_clause_location)
    scope = %{}

    fun =
      Enum.with_index(clauses)
      |> Enum.reduce(fun, fn {{opts, args, guard, body}, clause_idx}, fun ->
        location = make_location(opts)

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

        Expr.Fn.add_clause(fun, patterns, pat_var_map, guard_expr, body_expr, location)
      end)

    fun = Expr.Fn.finish(fun)

    :ok = PDAst.set_expr(out, expr_id, fun)
    :ok = PDAst.set_root(out, expr_id)

    {:ok, ast} = PDAst.finish(out)
    {:ok, ast}
  end

  def from_pattern(tup, binds, scope, out) when is_tuple(tup) and tuple_size(tup) != 3 do
    tup_list = Tuple.to_list(tup)
    {elems, binds} = Enum.map_reduce(tup_list, binds, fn elem, binds ->
      {binds, pattern_id} = from_pattern(elem, binds, scope, out)
      {pattern_id, binds}
    end)

    pattern_id = PDAst.add_pattern(out, {:tuple, elems})

    {binds, pattern_id}
  end

  def from_pattern(name, binds, _scope, out) when is_atom(name) do
    pattern_id = PDAst.add_pattern(out, {:atom, name})
    {binds, pattern_id}
  end

  def from_pattern({name, _opts, ctx} = var, binds, _scope, out)
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

    location = make_location(opts)
    expr_id = PDAst.add_expr(out, Expr.Block.new(exprs, location))

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

  def from_expr({name, opts, ctx} = var, scope, out) when is_atom(name) and is_atom(ctx) do
    var = process_var(var)
    ref_expr = Map.fetch!(scope, var)

    location = make_location(opts)
    expr_id = PDAst.add_expr(out, Expr.Var.new(ref_expr, location))

    {expr_id, scope}
  end

  def from_expr({:=, opts, [lhs, rhs]}, scope, out) do
    expr_id = PDAst.add_expr(out)

    {rhs_expr, scope} = from_expr(rhs, scope, out)

    {binds_map, [pat]} = handle_patterns([lhs], scope, out)

    scope =
      Enum.reduce(binds_map, scope, fn {idx, var}, scope ->
        {:expr, eid} = expr_id
        bind_id = {:expr_bind, eid, idx}

        :ok = PDAst.add_variable(out, var, bind_id)

        Map.put(scope, var, bind_id)
      end)

    location = make_location(opts)
    :ok = PDAst.set_expr(out, expr_id, Expr.Match.new(
          pat, binds_map, rhs_expr, location))

    {expr_id, scope}
  end

  # Map stuff, handled in clauses below because of complexity
  def from_expr({:%, _, [_, {:%{}, _, _}]} = expr, scope, out) do
    from_map_expr(expr, scope, out)
  end
  def from_expr({:%{}, _, _} = expr, scope, out) do
    from_map_expr(expr, scope, out)
  end

  def from_expr({:fn, opts, clauses}, scope, out) do
    expr_id = PDAst.add_expr(out)

    args_count =
      case List.first(clauses) do
        {:->, _opts, [args, _body]} ->
          Enum.count(args)
      end

    location = make_location(opts)
    fun = Expr.Fn.new(args_count, location)

    fun =
      clauses
      |> Enum.with_index()
      |> Enum.reduce(fun, fn
        {{:->, clause_opts, [args, body]}, clause_idx}, fun ->
          ^args_count = Enum.count(args)
          location = make_location(clause_opts)

          {pat_var_map, patterns} = handle_patterns(args, scope, out)

          scope =
            Enum.reduce(pat_var_map, scope, fn {idx, var}, scope ->
              {:expr, eid} = expr_id
              sub_expr_id = {:expr_bind, eid, {clause_idx, idx}}

              :ok = PDAst.add_variable(out, var, sub_expr_id)

              Map.put(scope, var, sub_expr_id)
            end)

          {body_expr, _scope} = from_expr(body, scope, out)

          Expr.Fn.add_clause(fun, patterns, pat_var_map, nil, body_expr, location)
      end)

    fun = Expr.Fn.finish(fun)

    :ok = PDAst.set_expr(out, expr_id, fun)
    {expr_id, scope}
  end

  def from_expr({:for, opts, items}, scope, out) do
    outer_scope = scope

    items = norm_items(items)
    grouped_items =
      Enum.group_by(items, fn
        {:into, _} -> :meta
        {:do, _} -> :meta
        {:uniq, _} -> :meta
        {:reduce, _} -> :meta
        {_, _} -> throw "unrecognized key!"
        _ -> :loop
      end)

    meta_items = Map.get(grouped_items, :meta, [])
    loop_items = Map.get(grouped_items, :loop, [])

    into = Keyword.get(meta_items, :into, nil)

    # TODO
    nil = Keyword.get(meta_items, :uniq, nil)
    nil = Keyword.get(meta_items, :reduce, nil)

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

    {body_expr, _scope} = from_expr(Keyword.fetch!(meta_items, :do), scope, out)

    location = make_location(opts)
    :ok = PDAst.set_expr(out, expr_id, Expr.For.new(item_exprs, into_expr, body_expr, location))

    {expr_id, outer_scope}
  end

  def from_expr({:case, opts, [expr, [do: clauses]]}, scope, out) do
    expr_id = PDAst.add_expr(out)

    {expr, scope} = from_expr(expr, scope, out)

    location = make_location(opts)
    case_expr = Expr.Case.new(expr, location)

    case_expr =
      clauses
      |> Enum.with_index()
      |> Enum.reduce(case_expr, fn
        {{:->, clause_opts, [[pattern], body]}, clause_idx}, case_expr ->
          location = make_location(clause_opts)

          {pat_var_map, [pattern]} = handle_patterns([pattern], scope, out)

          scope =
            Enum.reduce(pat_var_map, scope, fn {idx, var}, scope ->
              {:expr, eid} = expr_id
              sub_expr_id = {:expr_bind, eid, {clause_idx, idx}}

              :ok = PDAst.add_variable(out, var, sub_expr_id)

              Map.put(scope, var, sub_expr_id)
            end)

          {body_expr, _scope} = from_expr(body, scope, out)

          Expr.Case.add_clause(case_expr, pattern, pat_var_map, nil, body_expr, location)
      end)

    case_expr = Expr.Case.finish(case_expr)

    :ok = PDAst.set_expr(out, expr_id, case_expr)
    {expr_id, scope}
  end

  def from_expr({:{}, opts, elems}, scope, out) do
    {exprs, scope} = Enum.map_reduce(elems, scope, &from_expr(&1, &2, out))
    location = make_location(opts)
    expr_id = PDAst.add_expr(out, Expr.MakeTuple.new(exprs, location))
    {expr_id, scope}
  end

  def from_expr({:<<>>, opts, elems}, scope, out) do
    {items, scope} = Enum.map_reduce(elems, scope, fn
      {:"::", _, [expr, specifiers]}, scope ->
        # TODO information loss in opts?
        # TODO size specifier
        {expr, scope} = from_expr(expr, scope, out)
        {{expr, specifiers}, scope}
    end)
    location = make_location(opts)
    expr_id = PDAst.add_expr(out, Expr.MakeBinary.new(items, location))
    {expr_id, scope}
  end

  def from_expr(tup, scope, out) when is_tuple(tup) and tuple_size(tup) != 3 do
    tup_list = Tuple.to_list(tup)
    {exprs, scope} = Enum.map_reduce(tup_list, scope, &from_expr(&1, &2, out))
    expr_id = PDAst.add_expr(out, Expr.MakeTuple.new(exprs))
    {expr_id, scope}
  end

  def from_expr([head | tail], scope, out) do
    {head_expr, scope} = from_expr(head, scope, out)
    {tail_expr, scope} = from_expr(tail, scope, out)

    expr_id = PDAst.add_expr(out, Expr.MakeCons.new(head_expr, tail_expr))

    {expr_id, scope}
  end

  def from_expr([], scope, out) do
    lit_id = PDAst.add_literal(out, [])
    {lit_id, scope}
  end

  def from_expr(binary, scope, out) when is_binary(binary) do
    lit_id = PDAst.add_literal(out, binary)
    {lit_id, scope}
  end

  def from_expr(atom, scope, out) when is_atom(atom) do
    lit_id = PDAst.add_literal(out, atom)
    {lit_id, scope}
  end

  def from_expr(num, scope, out) when is_number(num) do
    lit_id = PDAst.add_literal(out, num)
    {lit_id, scope}
  end

  def from_expr({function, opts, args}, scope, out) when is_atom(function) do
    {function_expr, scope} = from_expr(function, scope, out)

    {arg_exprs, scope} = Enum.map_reduce(args, scope, &from_expr(&1, &2, out))

    location = make_location(opts)
    expr_id = PDAst.add_expr(out, Expr.CallMF.new(
          nil, function_expr, arg_exprs, location))

    {expr_id, scope}
  end

  def from_expr({{:., opts2, [module, function]}, opts1, args}, scope, out)
      when is_atom(module) and is_atom(function) do
    {module_expr, scope} = from_expr(module, scope, out)
    {function_expr, scope} = from_expr(function, scope, out)

    {arg_exprs, scope} = Enum.map_reduce(args, scope, &from_expr(&1, &2, out))

    location = make_merge_locations([opts1, opts2])
    expr_id = PDAst.add_expr(out, Expr.CallMF.new(
          module_expr, function_expr, arg_exprs, location))

    {expr_id, scope}
  end

  def from_expr({{:., opts2, [top, field]}, opts1, []}, scope, out) when is_atom(field) do
    {top_expr, scope} = from_expr(top, scope, out)

    location = make_merge_locations([opts1, opts2])
    expr_id = PDAst.add_expr(out, Expr.AccessField.new(
          top_expr, field, location))

    {expr_id, scope}
  end

  def from_expr(_expr, _scope, _out) do
    raise "unhandled clause"
  end

  # Map stuff

  # `from_map_expr` is just called directly from from_expr in case we are making a map.
  # It handles the struct part of map construction, and calls down into
  # `from_map_prior_expr`.
  def from_map_expr({:%, opts, [struct_expr, {:%{}, _, _} = map_expr]}, scope, out) do
    loc = make_location(opts)
    {struct_expr, scope} = from_expr(struct_expr, scope, out)
    from_map_prior_expr(struct_expr, map_expr, loc, scope, out)
  end
  def from_map_expr({:%{}, opts, _} = map_expr, scope, out) do
    loc = make_location(opts)
    from_map_prior_expr(nil, map_expr, loc, scope, out)
  end

  # `from_map_prior_expr` handles the prior map part of map construction (`|`).
  # It calls into `from_map_inner_expr`.
  def from_map_prior_expr(struct_expr, {:%{}, opts1, [{:|, opts2, [prior, kvs]}]}, loc1, scope, out) do
    loc2 = merge_location(make_location(opts1), make_location(opts2))
    loc = merge_location(loc1, loc2)
    {prior_expr, scope} = from_expr(prior, scope, out)
    from_map_inner_expr(struct_expr, prior_expr, loc, kvs, scope, out)
  end
  def from_map_prior_expr(struct_expr, {:%{}, opts, kvs}, loc1, scope, out) do
    loc = merge_location(loc1, make_location(opts))
    from_map_inner_expr(struct_expr, nil, loc, kvs, scope, out)
  end

  # `from_map_inner_expr` handles the key-value portion of map construction.
  def from_map_inner_expr(struct_expr, prior_expr, loc, kvs, scope, out) do
    {kv_exprs, scope} =
      Enum.map_reduce(kvs, scope, fn {key, value}, scope ->
        {key_expr, scope} = from_expr(key, scope, out)
        {value_expr, scope} = from_expr(value, scope, out)

        {{key_expr, value_expr}, scope}
      end)

    expr_id = PDAst.add_expr(out, Expr.MakeMap.new(struct_expr, prior_expr, kv_exprs, loc))

    {expr_id, scope}
  end

  # Pattern stuff

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

  defp process_var({name, opts, ctx}) when is_atom(name) and is_atom(ctx) do
    counter = Keyword.get(opts, :counter)
    {name, counter, ctx}
  end

  defp make_merge_locations(locations) do
    Enum.reduce(locations, {nil, nil}, fn
      opts, acc ->
        loc = make_location(opts)
        merge_location(acc, loc)
    end)
  end

  defp merge_location(nil, loc2) when loc2 != nil, do: loc2
  defp merge_location(loc1, nil) when loc1 != nil, do: loc1
  defp merge_location(nil, nil), do: {nil, nil}
  defp merge_location({nil, _}, loc2), do: loc2
  defp merge_location({_, nil}, {_, col2} = loc2) when col2 != nil, do: loc2
  defp merge_location(loc1, _loc2), do: loc1

  defp make_location(opts) do
    line = Keyword.get(opts, :line)
    column = Keyword.get(opts, :column)
    {line, column}
  end
end
