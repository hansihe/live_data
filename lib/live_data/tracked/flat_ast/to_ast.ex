defmodule LiveData.Tracked.FlatAst.ToAst do
  @moduledoc """
  Module which converts a FlatAst to an Elixir AST.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FragmentTree.Slot

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

        {{:=, make_opts(), [var_to_expr(unique_var, gen), item_ast]}, gen}
    end
  end

  def to_expr(expr_id, gen, ast, true, opts) do
    item = FlatAst.get(ast, expr_id)
    to_expr_inner(item, expr_id, gen, ast, true, opts)
  end

  def to_expr_inner({:bind, _bid} = bind, _expr_id, gen, _ast, _scope_mode, _opts) do
    var = Map.fetch!(gen, bind)
    var_ast = var_to_expr(var, gen)
    {var_ast, gen}
  end

  def to_expr_inner({:literal_value, literal}, _expr_id, gen, _ast, _scope_mode, _opts) do
    {literal, gen}
  end

  def to_expr_inner(%Expr.Fn{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {clauses, gen} =
      expr.clauses
      |> Enum.map_reduce(gen, fn %Expr.Fn.Clause{} = clause, gen ->
        {patterns_ast, gen} =
          Enum.map_reduce(clause.patterns, gen, fn pattern_id, gen ->
            to_pattern(pattern_id, gen, ast, opts)
          end)

        gen = Enum.reduce(clause.binds, gen, fn bind, gen ->
          data = FlatAst.get_bind_data(ast, bind)
          Map.put(gen, bind, data.variable) # TODO decollide?
        end)

        # TODO handle guards
        nil = clause.guard

        {body_ast, gen} = to_expr(clause.body, gen, ast, scope_mode, opts)

        ast_opts = make_opts(location: clause.location)
        {{:->, ast_opts, [patterns_ast, body_ast]}, gen}
      end)

    ast_opts = make_opts(location: expr.location)
    {{:fn, ast_opts, clauses}, gen}
  end

  def to_expr_inner(
        %Expr.SimpleAssign{inner: _inner},
        {:expr, _eid},
        _gen,
        _ast,
        _scope_mode,
        _opts
      ) do
    #{inner_ast, gen} = to_expr(inner, gen, ast, scope_mode, opts)

    #unique_var = make_unique_var(opts)
    #gen = Map.put(gen, {:expr_bind, eid, 0}, unique_var)

    raise "unimpl"

    #{{:=, make_opts(), [var_to_expr(unique_var, gen), inner_ast]}, gen}
  end

  def to_expr_inner(
        %Expr.Block{exprs: exprs, location: location},
        _expr_id,
        gen,
        ast,
        _scope_mode,
        opts
      ) do
    {inner, gen} = Enum.map_reduce(exprs, gen, &to_expr(&1, &2, ast, false, opts))

    ast_opts = make_opts(location: location)
    {{:__block__, ast_opts, inner}, gen}
  end

  def to_expr_inner(
        %Expr.Scope{exprs: exprs, location: location},
        _expr_id,
        gen,
        ast,
        _scope_mode,
        opts
      ) do
    {inner, gen} = Enum.map_reduce(exprs, gen, &to_expr(&1, &2, ast, true, opts))

    inner = filter_non_return_literals(inner)

    ast_opts = make_opts(location: location)
    {{:__block__, ast_opts, inner}, gen}
  end

  def to_expr_inner(
        %Expr.Match{pattern: pattern, binds: binds, rhs: rhs, location: location},
        {:expr, _eid} = outer_expr_id,
        gen,
        ast,
        scope_mode,
        opts
      ) do
    {pattern_ast, gen} = to_pattern(pattern, gen, ast, opts)
    {rhs_ast, gen} = to_expr(rhs, gen, ast, scope_mode, opts)

    gen =
      Enum.reduce(binds, gen, fn bind, gen ->
        data = FlatAst.get_bind_data(ast, bind)
        ^outer_expr_id = data.expr
        Map.put(gen, bind, data.variable)
      end)

    ast_opts = make_opts(location: location)
    {{:=, ast_opts, [pattern_ast, rhs_ast]}, gen}
  end

  def to_expr_inner(%Expr.MakeMap{struct: nil, prev: nil, kvs: kvs, location: location}, _expr_id, gen, ast, scope_mode, opts) do
    {kvs_ast, gen} =
      Enum.map_reduce(kvs, gen, fn {key, value}, gen ->
        {key_ast, gen} = to_expr(key, gen, ast, scope_mode, opts)
        {value_ast, gen} = to_expr(value, gen, ast, scope_mode, opts)
        {{key_ast, value_ast}, gen}
      end)

    ast_opts = make_opts(location: location)
    {{:%{}, ast_opts, kvs_ast}, gen}
  end

  def to_expr_inner(%Expr.MakeCons{head: head, tail: tail}, _expr_id, gen, ast, scope_mode, opts) do
    {head_ast, gen} = to_expr(head, gen, ast, scope_mode, opts)
    {tail_ast, gen} = to_expr(tail, gen, ast, scope_mode, opts)
    {[{:|, make_opts(), [head_ast, tail_ast]}], gen}
  end

  def to_expr_inner(%Expr.MakeTuple{elements: elems, location: location}, _expr_id, gen, ast, scope_mode, opts) do
    {elems, gen} = Enum.map_reduce(elems, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    ast_opts = make_opts(location: location)
    {{:{}, ast_opts, elems}, gen}
  end

  def to_expr_inner(%Expr.MakeBinary{components: components, location: location}, _expr_id, gen, ast, scope_mode, opts) do
    {elems, gen} = Enum.map_reduce(components, gen, fn
      {expr, specifier}, gen ->
        # TODO size specifier
        {elem_ast, gen} = to_expr(expr, gen, ast, scope_mode, opts)
        {{:"::", [], [elem_ast, specifier]}, gen}
    end)

    ast_opts = make_opts(location: location)
    {{:<<>>, ast_opts, elems}, gen}
  end

  def to_expr_inner(%Expr.Case{} = expr, {:expr, _eid} = outer_expr_id, gen, ast, scope_mode, opts) do
    {value_ast, gen} = to_expr(expr.value, gen, ast, scope_mode, opts)

    {clauses, gen} =
      expr.clauses
      |> Enum.map_reduce(gen, fn %Expr.Case.Clause{} = clause, gen ->
        {pattern_ast, gen} = to_pattern(clause.pattern, gen, ast, opts)

        gen =
          Enum.reduce(clause.binds, gen, fn bind, gen ->
            data = FlatAst.get_bind_data(ast, bind)
            ^outer_expr_id = data.expr
            Map.put(gen, bind, data.variable)
          end)

        # TODO handle guards
        nil = clause.guard

        {body_ast, gen} = to_expr(clause.body, gen, ast, scope_mode, opts)

        ast_opts = make_opts(location: clause.location)
        {{:->, ast_opts, [[pattern_ast], body_ast]}, gen}
      end)

    ast_opts = make_opts(location: expr.location)
    {{:case, ast_opts, [value_ast, [do: clauses]]}, gen}
  end

  def to_expr_inner(%Expr.For{} = expr, outer_expr_id, gen, ast, scope_mode, opts) do
    # TODO
    # We currently do not handle into.
    # Just assert that we collect into an empty list.
    case expr.into do
      nil -> nil
      {:literal, _lit} = literal_id ->
        {:literal_value, []} = FlatAst.get(ast, literal_id)
    end

    {items, gen} =
      expr.items
      |> Enum.map_reduce(gen, fn
        {:loop, pattern_id, binds_map, expr_id}, gen ->
          {pattern_ast, gen} = to_pattern(pattern_id, gen, ast, opts)

          gen =
            Enum.reduce(binds_map, gen, fn bind, gen ->
              data = FlatAst.get_bind_data(ast, bind)
              ^outer_expr_id = data.expr
              Map.put(gen, bind, data.variable)
            end)

          {expr_ast, gen} = to_expr(expr_id, gen, ast, scope_mode, opts)
          {{:<-, make_opts(), [pattern_ast, expr_ast]}, gen}

        {:filter, expr_id}, gen ->
          to_expr(expr_id, gen, ast, scope_mode, opts)
      end)

    {body_ast, gen} = to_expr(expr.inner, gen, ast, scope_mode, opts)

    ast_opts = make_opts(location: expr.location)
    {{:for, ast_opts, Enum.concat([items, [[do: body_ast]]])}, gen}
  end

  def to_expr_inner(%Expr.AccessField{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {top_expr, gen} = to_expr(expr.top, gen, ast, scope_mode, opts)
    field = expr.field

    ast_opts = make_opts(location: expr.location)
    {{{:., ast_opts, [top_expr, field]}, [no_parens: true], []}, gen}
  end

  def to_expr_inner(%Expr.Var{ref_expr: ref_expr, location: location}, _expr_id, gen, _ast, _scope_mode, _opts) do
    #var = Map.get(ast.variables, ref_expr) || Map.fetch!(gen, ref_expr)
    var = Map.fetch!(gen, ref_expr)
    ast_opts = make_opts(location: location)
    var_ast = var_to_expr(var, gen, ast_opts)
    {var_ast, gen}
  end

  # TODO probably eliminate CallTracked expression in a pass?
  def to_expr_inner(%Expr.CallTracked{inner: inner}, expr_id, gen, ast, scope_mode, opts) do
    to_expr_inner(inner, expr_id, gen, ast, scope_mode, opts)
  end

  def to_expr_inner(%Expr.CallMF{module: nil} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {function_ast, gen} = to_expr(expr.function, gen, ast, scope_mode, opts)

    {args_ast, gen} = Enum.map_reduce(expr.args, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    ast_opts = make_opts(location: expr.location)
    {{function_ast, ast_opts, args_ast}, gen}
  end

  def to_expr_inner(%Expr.CallMF{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {module_ast, gen} = to_expr(expr.module, gen, ast, scope_mode, opts)
    {function_ast, gen} = to_expr(expr.function, gen, ast, scope_mode, opts)

    {args_ast, gen} = Enum.map_reduce(expr.args, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    ast_opts = make_opts(location: expr.location)
    {{{:., [], [module_ast, function_ast]}, ast_opts, args_ast}, gen}
  end

  def to_expr_inner(%Expr.CallValue{} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {value_ast, gen} = to_expr(expr.value, gen, ast, scope_mode, opts)
    {args_ast, gen} = Enum.map_reduce(expr.args, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    ast_opts = make_opts(location: expr.location)
    {{{:., [], [value_ast]}, ast_opts, args_ast}, gen}
  end

  def to_expr_inner(
        %Expr.MakeStatic{key: nil, slots: [inner], static: %Slot{num: 0}},
        _expr_id,
        gen,
        ast,
        scope_mode,
        opts
      ) do
    to_expr(inner, gen, ast, scope_mode, opts)
  end

  def to_expr_inner(%Expr.MakeStatic{key: nil} = expr, _expr_id, gen, ast, scope_mode, opts) do
    {slots, gen} = Enum.map_reduce(expr.slots, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    id_expr = Macro.escape({expr.mfa, expr.static_id})
    template_expr = Macro.escape(expr.static)

    expr =
      quote do
        %LiveData.Tracked.RenderTree.Static{
          id: unquote(id_expr),
          template: unquote(template_expr),
          slots: unquote(slots)
        }
      end

    {expr, gen}
  end

  def to_expr_inner(%Expr.MakeStatic{key: key} = expr, expr_id, gen, ast, scope_mode, opts) do
    {key_expr, gen} = to_expr(key, gen, ast, scope_mode, opts)
    {inner_expr, gen} = to_expr_inner(%{expr | key: nil}, expr_id, gen, ast, scope_mode, opts)

    id_expr = Macro.escape({expr.mfa, expr.static_id})

    expr =
      quote do
        %LiveData.Tracked.RenderTree.Keyed{
          id: unquote(id_expr),
          key: unquote(key_expr),
          escapes: :always,
          render: fn -> unquote(inner_expr) end
        }
      end

    {expr, gen}
  end

  def to_pattern(pattern_id, gen, ast, opts) do
    pattern = FlatAst.get(ast, pattern_id)
    to_pattern_inner(pattern, pattern_id, gen, ast, opts)
  end

  def to_pattern_inner({:tuple, elems}, _pattern_id, gen, ast, opts) do
    {new_elems, gen} =  Enum.map_reduce(elems, gen, fn
      elem, gen ->
        to_pattern(elem, gen, ast, opts)
    end)

    {{:{}, make_opts(), new_elems}, gen}
  end

  def to_pattern_inner({:bind, var}, _pattern_id, gen, _ast, _opts) do
    {var_to_expr(var, gen), gen}
  end

  def to_pattern_inner({:atom, name}, _pattern_id, gen, _ast, _opts) do
    {name, gen}
  end

  def var_to_expr(var_info, gen, opts \\ [])

  def var_to_expr({name, nil, ctx}, _gen, opts) do
    {name, opts, ctx}
  end

  def var_to_expr({name, counter, ctx}, _gen, opts) do
    {name, [{:counter, counter} | opts], ctx}
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

  def make_opts(args \\ []) do
    base = [generated: true]
    case Keyword.fetch(args, :location) do
      {:ok, {line, nil}} -> [{:line, line} | base]
      {:ok, {line, column}} -> [{:line, line}, {:column, column} | base]
      _ -> base
    end
  end

  def filter_non_return_literals(exprs, acc \\ [])
  def filter_non_return_literals([], []), do: []
  def filter_non_return_literals([ret_val], acc), do: Enum.reverse([ret_val | acc])
  def filter_non_return_literals([val | tail], acc) when is_number(val), do: filter_non_return_literals(tail, acc)
  def filter_non_return_literals([val | tail], acc) when is_binary(val), do: filter_non_return_literals(tail, acc)
  def filter_non_return_literals([val | tail], acc), do: filter_non_return_literals(tail, [val, acc])
end
