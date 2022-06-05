defmodule LiveData.Tracked.FlatAst.ToAst do
  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.Tree.Slot

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

  def to_expr_inner({:expr_bind, _eid, _selector} = bind, _expr_id, gen, ast, _scope_mode, _opts) do
    var = Map.get(ast.variables, bind) || Map.fetch!(gen, bind)
    var_ast = var_to_expr(var, gen)
    {var_ast, gen}
  end

  def to_expr_inner({:literal, literal}, _expr_id, gen, _ast, _scope_mode, _opts) do
    {literal, gen}
  end

  def to_expr_inner(%Expr.Fn{} = expr, expr_id, gen, ast, scope_mode, opts) do
    {clauses, gen} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(gen, fn {%Expr.Fn.Clause{} = clause, clause_idx}, gen ->
        {:expr, eid} = expr_id

        {patterns_ast, gen} =
          Enum.map_reduce(clause.patterns, gen, fn pattern_id, gen ->
            to_pattern(pattern_id, gen, ast, opts)
          end)

        gen =
          Enum.reduce(clause.binds, gen, fn {idx, var}, gen ->
            sub = {:expr_bind, eid, {clause_idx, idx}}
            Map.put(gen, sub, var)
          end)

        nil = clause.guard

        {body_ast, gen} = to_expr(clause.body, gen, ast, scope_mode, opts)

        ast_opts = make_opts(location: clause.location)
        {{:->, ast_opts, [patterns_ast, body_ast]}, gen}
      end)

    ast_opts = make_opts(location: expr.location)
    {{:fn, ast_opts, clauses}, gen}
  end

  def to_expr_inner(
        %Expr.SimpleAssign{inner: inner},
        {:expr, eid},
        gen,
        ast,
        scope_mode,
        opts
      ) do
    {inner_ast, gen} = to_expr(inner, gen, ast, scope_mode, opts)

    unique_var = make_unique_var(opts)
    gen = Map.put(gen, {:expr_bind, eid, 0}, unique_var)

    {{:=, [], [var_to_expr(unique_var, gen), inner_ast]}, gen}
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

    ast_opts = make_opts(location: location)
    {{:__block__, ast_opts, inner}, gen}
  end

  def to_expr_inner(
        %Expr.Match{pattern: pattern, binds: binds, rhs: rhs, location: location},
        {:expr, eid},
        gen,
        ast,
        scope_mode,
        opts
      ) do
    {pattern_ast, gen} = to_pattern(pattern, gen, ast, opts)
    {rhs_ast, gen} = to_expr(rhs, gen, ast, scope_mode, opts)

    gen =
      Enum.reduce(binds, gen, fn {idx, var}, gen ->
        sub = {:expr_bind, eid, idx}
        Map.put(gen, sub, var)
      end)

    ast_opts = make_opts(location: location)
    {{:=, ast_opts, [pattern_ast, rhs_ast]}, gen}
  end

  def to_expr_inner(%Expr.MakeMap{prev: nil, kvs: kvs, location: location}, _expr_id, gen, ast, scope_mode, opts) do
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
    {[{:|, [], [head_ast, tail_ast]}], gen}
  end

  def to_expr_inner(%Expr.MakeTuple{elements: elems, location: location}, _expr_id, gen, ast, scope_mode, opts) do
    {elems, gen} = Enum.map_reduce(elems, gen, &to_expr(&1, &2, ast, scope_mode, opts))

    ast_opts = make_opts(location: location)
    {{:{}, ast_opts, elems}, gen}
  end

  def to_expr_inner(%Expr.Case{} = expr, {:expr, eid}, gen, ast, scope_mode, opts) do
    {value_ast, gen} = to_expr(expr.value, gen, ast, scope_mode, opts)

    {clauses, gen} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(gen, fn {%Expr.Case.Clause{} = clause, clause_idx}, gen ->
        {pattern_ast, gen} = to_pattern(clause.pattern, gen, ast, opts)

        gen =
          Enum.reduce(clause.binds, gen, fn {idx, var}, gen ->
            sub = {:expr_bind, eid, {clause_idx, idx}}
            Map.put(gen, sub, var)
          end)

        nil = clause.guard

        {body_ast, gen} = to_expr(clause.body, gen, ast, scope_mode, opts)

        ast_opts = make_opts(location: clause.location)
        {{:->, ast_opts, [[pattern_ast], body_ast]}, gen}
      end)

    ast_opts = make_opts(location: expr.location)
    {{:case, ast_opts, [value_ast, [do: clauses]]}, gen}
  end

  def to_expr_inner(%Expr.For{} = expr, {:expr, eid}, gen, ast, scope_mode, opts) do
    nil = expr.into

    {items, gen} =
      expr.items
      |> Enum.with_index()
      |> Enum.map_reduce(gen, fn
        {{:loop, pattern_id, binds_map, expr_id}, item_idx}, gen ->
          {pattern_ast, gen} = to_pattern(pattern_id, gen, ast, opts)

          gen =
            Enum.reduce(binds_map, gen, fn {idx, var}, gen ->
              sub = {:expr_bind, eid, {item_idx, idx}}
              Map.put(gen, sub, var)
            end)

          {expr_ast, gen} = to_expr(expr_id, gen, ast, scope_mode, opts)
          {{:<-, [], [pattern_ast, expr_ast]}, gen}

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

  def to_expr_inner(%Expr.Var{ref_expr: ref_expr, location: location}, _expr_id, gen, ast, _scope_mode, _opts) do
    var = Map.get(ast.variables, ref_expr) || Map.fetch!(gen, ref_expr)
    ast_opts = make_opts(location: location)
    var_ast = var_to_expr(var, gen, ast_opts)
    {var_ast, gen}
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

    {{:{}, [], new_elems}, gen}
  end

  def to_pattern_inner({:bind, var}, _pattern_id, gen, _ast, _opts) do
    {var_to_expr(var, gen), gen}
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

  def make_opts(args) do
    case Keyword.fetch(args, :location) do
      {:ok, {line, nil}} -> [line: line]
      {:ok, {line, column}} -> [line: line, column: column]
      _ -> []
    end
  end
end
