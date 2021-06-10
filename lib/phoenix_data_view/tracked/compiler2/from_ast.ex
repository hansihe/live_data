defmodule Phoenix.DataView.Tracked.Compiler2.FromAst do
  alias Phoenix.DataView.Tracked.Compiler2.IR
  alias Phoenix.DataView.Tracked.Compiler2.PDIR

  def from_clauses([first_clause | _] = clauses) do
    {:ok, ir} = PDIR.init()

    {_opts, args, [], _body} = first_clause
    num_args = Enum.count(args)

    {block, [fin_block | _args]} = PDIR.add_block(ir, num_args + 1)
    :ok = PDIR.set_entry(ir, block)

    cas = IR.Op.Case.new(fin_block)

    scope = %{}

    cas =
      Enum.reduce(clauses, cas, fn {_opts, args, [], body}, cas ->
        binds = args_pattern_get_binds(args)
        num_binds = Enum.count(binds)

        {clause_block, [clause_ret | binds_vars]} = PDIR.add_block(ir, num_binds + 1)

        scope =
          Enum.zip(binds, binds_vars)
          |> Enum.reduce(scope, fn {bind, var}, scope ->
            Map.put(scope, bind, var)
          end)

        {ret_value, cont_block, scope} = from_expr(body, clause_block, scope, ir)

        :ok = PDIR.set_body(ir, cont_block, IR.Op.CallRet.new(clause_ret, ret_value))

        cas = IR.Op.Case.add_clause(cas, args, binds, clause_block)

        cas
      end)

    :ok = PDIR.set_body(ir, block, cas)

    {:ok, final} = PDIR.finish(ir)

    {:ok, final}
  end

  def from_expr({:__block__, _opts, inner}, block, scope, ir) do
    Enum.reduce(inner, {nil, block, scope}, fn item, {_last, block, scope} ->
      from_expr(item, block, scope, ir)
    end)
  end

  def from_expr({:%{}, _opts, {:|, _opts2, [prev, inner]}}, block, scope, ir) do
    true = false
  end

  def from_expr({:%{}, _opts, inner}, block, scope, ir) do
    {kvs, block} =
      Enum.map_reduce(inner, block, fn {key, value}, block ->
        {key_var, block, _scope} = from_expr(key, block, scope, ir)
        {value_var, block, _scope} = from_expr(value, block, scope, ir)
        {{key_var, value_var}, block}
      end)

    {next, [map_var]} = PDIR.add_block(ir, 1)
    op = IR.Op.MakeMap.new(next, nil, kvs)
    :ok = PDIR.set_body(ir, block, op)

    {map_var, next, scope}
  end

  def from_expr({:for, _opts, items}, block, scope, ir) do
    grouped_items = Enum.group_by(items, fn
      [{:into, _}] -> :meta
      [{:do, _}] -> :meta
      _ -> :loop
    end)

    meta_items =
      Map.get(grouped_items, :meta, [])
      |> Enum.map(fn [kv] -> kv end)

    loop_items = Map.get(grouped_items, :loop, [])

    {into_var, block, _scope} = from_expr(Keyword.get(meta_items, :into, []), block, scope, ir)
    body = Keyword.fetch!(meta_items, :do)

    {inner, [ret_var, acc_var]} = PDIR.add_block(ir, 2)
    {acc_var, inner_res_block, scope} = from_for_items(loop_items, body, acc_var, inner, scope, ir)
    :ok = PDIR.set_body(ir, inner_res_block, IR.Op.CallRet.new(ret_var, acc_var))

    {next, [result_var]} = PDIR.add_block(ir, 1)
    :ok = PDIR.set_body(ir, block, IR.Op.For.new(next, inner, into_var))

    {result_var, next, scope}
  end

  def from_expr({function, _opts, args}, block, scope, ir) when is_atom(function) and is_list(args) do
    num_args = Enum.count(args)

    {function_var, block, _scope} = from_expr(function, block, scope, ir)
    arity_var = PDIR.add_literal(ir, num_args)

    {next, [fun_var]} = PDIR.add_block(ir, 1)
    :ok = PDIR.set_body(ir, block, IR.Op.CaptureFun.new(
          next, nil, function_var, arity_var))

    {args_vars, block} = Enum.map_reduce(args, next, fn arg, block ->
      {arg_var, block, _scope} = from_expr(arg, block, scope, ir)
      {arg_var, block}
    end)

    {fin, [ret_var]} = PDIR.add_block(ir, 1)
    :ok = PDIR.set_body(ir, block, IR.Op.Call.new(fun_var, fin, args_vars))

    {ret_var, fin, scope}
  end

  def from_expr({{:., _opts1, [module, function]}, _opts2, args}, block, scope, ir) do
    num_args = Enum.count(args)

    {module_var, block, _scope} = from_expr(module, block, scope, ir)
    {function_var, block, _scope} = from_expr(function, block, scope, ir)
    arity_var = PDIR.add_literal(ir, num_args)

    {next, [fun_var]} = PDIR.add_block(ir, 1)
    :ok = PDIR.set_body(ir, block, IR.Op.CaptureFun.new(
          next, module_var, function_var, arity_var))

    {args_vars, block} = Enum.map_reduce(args, next, fn arg, block ->
      {arg_var, block, _scope} = from_expr(arg, block, scope, ir)
      {arg_var, block}
    end)

    {fin, [ret_var]} = PDIR.add_block(ir, 1)
    :ok = PDIR.set_body(ir, block, IR.Op.Call.new(fun_var, fin, args_vars))

    {ret_var, fin, scope}
  end

  def from_expr([], block, scope, ir) do
    var = PDIR.add_literal(ir, [])
    {var, block, scope}
  end

  def from_expr(atom, block, scope, ir) when is_atom(atom) do
    var = PDIR.add_literal(ir, atom)
    {var, block, scope}
  end

  def from_expr({name, _opts, ctx} = var, block, scope, ir) when is_atom(name) and is_atom(ctx) do
    var_desc = process_var(var)
    var = Map.fetch!(scope, var_desc)

    {var, block, scope}
  end

  def from_for_items([], body, acc, block, scope, ir) do
    {value, block, _scope} = from_expr(body, block, scope, ir)

    {next, [acc_ret]} = PDIR.add_block(ir, 1)
    :ok = PDIR.set_body(ir, block, IR.Op.Call.new(acc, next, [value]))

    {acc_ret, next, scope}
  end

  def from_for_items([{:<-, _opts, [pattern, value]} | tail], body, acc, block, scope, ir) do
    pattern_binds = pattern_get_binds(pattern)
    num_binds = Enum.count(pattern_binds)

    {value, block, _scope} = from_expr(value, block, scope, ir)

    {inner_block, [ret_var, acc_var | binds_vars]} = PDIR.add_block(ir, num_binds + 2)
    inner_scope =
      Enum.zip(pattern_binds, binds_vars)
      |> Enum.reduce(scope, fn {bind, var}, scope ->
        Map.put(scope, bind, var)
      end)

    {acc_ret, inner_res_block, _scope} = from_for_items(tail, body, acc, inner_block, inner_scope, ir)
    :ok = PDIR.set_body(ir, inner_res_block, IR.Op.CallRet.new(ret_var, acc_var))

    {next, [acc_ret2]} = PDIR.add_block(ir, 1)
    op = IR.Op.ForLoop.new(next, inner_block, acc, pattern, pattern_binds)
    :ok = PDIR.set_body(ir, block, op)

    {acc_ret2, next, scope}
  end

  def args_pattern_get_binds(args_pattern) do
    Enum.reduce(args_pattern, [], &pattern_get_binds/2)
  end

  def pattern_get_binds({name, _opts, ctx} = var, acc \\ []) when is_atom(name) and is_atom(ctx) do
    var_desc = process_var(var)
    [var_desc | acc]
  end

  defp process_var({name, opts, ctx}) when is_atom(name) and is_atom(ctx) do
    counter = Keyword.get(opts, :counter)
    {name, counter, ctx}
  end
end
