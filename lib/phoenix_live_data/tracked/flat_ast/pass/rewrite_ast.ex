defmodule Phoenix.LiveData.Tracked.FlatAst.Pass.RewriteAst do
  @moduledoc """
  """

  alias Phoenix.LiveData.Tracked.FlatAst
  alias Phoenix.LiveData.Tracked.FlatAst.Expr
  alias Phoenix.LiveData.Tracked.FlatAst.PDAst
  alias Phoenix.LiveData.Tracked.FlatAst.Util
  alias Phoenix.LiveData.Tracked.Tree.Slot

  def rewrite(ast, full_mfa, nesting_set) do
    #scopes =
    #  FlatAst.Util.traverse(ast, ast.root, %{}, fn
    #    id, %Expr.Scope{exprs: exprs}, scopes ->
    #      scopes = Map.put(scopes, id, MapSet.new(exprs))
    #      {:continue, scopes}

    #    _id, _expr, scopes ->
    #      {:continue, scopes}
    #  end)

    {:ok, out} = PDAst.init()
    new_root = PDAst.add_expr(out)
    :ok = PDAst.set_root(out, new_root)

    fn_expr = %Expr.Fn{} = FlatAst.get(ast, ast.root)

    {new_clauses, statics} =
      Enum.map_reduce(fn_expr.clauses, %{}, fn %Expr.Fn.Clause{} = clause, statics_acc ->
        new_guard =
          if clause.guard do
            raise "unimpl"
            # transcribe(guard, ast, out)
          end

        {:ok, state} =
          Agent.start_link(fn ->
            %{statics: %{}, traversed: MapSet.new(), dependencies: MapSet.new()}
          end)

        _rewrite_root = rewrite_make_structure(clause.body, ast, state)

        %{statics: statics, traversed: traversed, dependencies: dependencies} =
          Agent.get(state, fn state -> state end)

        :ok = Agent.stop(state)

        data = %{
          statics: statics,
          ast: ast,
          traversed: traversed,
          nesting_set: nesting_set,
          mfa: full_mfa
        }

        data =
          Map.put(
            data,
            :dependencies,
            expand_dependencies(MapSet.to_list(dependencies), data, ast)
          )

        rewritten = %{}
        transcribed = %{ast.root => new_root}
        {new_body, _transcribed} = rewrite_scope(clause.body, data, rewritten, transcribed, out)

        clause = %{clause | guard: new_guard, body: new_body}
        {clause, Map.merge(statics_acc, statics)}
      end)

    new_expr = %{fn_expr | clauses: new_clauses}

    :ok = PDAst.set_expr(out, new_root, new_expr)
    {:ok, new_ast} = PDAst.finish(out)

    # TODO?
    new_ast = %{new_ast | patterns: ast.patterns}

    statics =
      statics
      |> Enum.map(fn
        {id, {:finished, structure, _slots, _key}} -> {id, structure}
        _ -> nil
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.into(%{})

    {:ok, new_ast, statics}
  end

  @doc """
  First pass of rewriting.

  This will traverse the function from the return position, constructing the
  static fragment with slots. Each static fragment is keyed by the expr it will
  take the place of in the rewritten AST.

  Traversed expressions are also registered for use by the later passes.
  """
  def rewrite_make_structure(expr_id, ast, state) do
    if state_static_fetch(state, expr_id) != :error do
      expr_id
    else
      :ok = state_static_add(state, expr_id)
      static_structure = rewrite_make_structure_rec(expr_id, ast, expr_id, state)

      {:ok, static_result} = state_static_fetch(state, expr_id)

      case {static_structure, static_result} do
        {%Slot{num: 0}, {:unfinished, _nid, [slot_zero_expr], nil}} ->
          case state_static_fetch(state, slot_zero_expr) do
            {:ok, {:finished, _static, _slots, _key} = val} ->
              :ok = state_static_set(state, expr_id, val)

            _ ->
              slot_zero_expr
          end

        _ ->
          :ok = state_static_finalize(state, expr_id, static_structure)
          expr_id
      end
    end
  end

  def rewrite_make_structure_rec(expr_id, ast, static_id, state) do
    expr = FlatAst.get(ast, expr_id)
    rewrite_make_structure_rec(expr, expr_id, ast, static_id, state)
  end

  def rewrite_make_structure_rec(%Expr.Scope{exprs: exprs}, _expr_id, ast, static_id, state) do
    result_expr = List.last(exprs)
    rewrite_make_structure_rec(result_expr, ast, static_id, state)
  end

  def rewrite_make_structure_rec(%Expr.Case{} = expr, expr_id, ast, static_id, state) do
    :ok = state_static_add_dependencies(state, [expr.value])

    for clause <- expr.clauses do
      _inner_expr = rewrite_make_structure(clause.body, ast, state)
    end
    :ok = state_static_add_traversed(state, expr_id)

    state_static_add_slot(state, static_id, expr_id)
  end

  def rewrite_make_structure_rec(%Expr.For{} = expr, expr_id, ast, static_id, state) do
    items =
      Enum.map(expr.items, fn
        {:loop, _pattern, _binds, expr} -> expr
        {:filter, expr} -> expr
      end)

    :ok = state_static_add_dependencies(state, [expr.into | items])

    _inner_expr = rewrite_make_structure(expr.inner, ast, state)
    :ok = state_static_add_traversed(state, expr_id)

    state_static_add_slot(state, static_id, expr_id)
  end

  def rewrite_make_structure_rec(%Expr.CallMF{} = expr, expr_id, ast, static_id, state) do
    case {FlatAst.get(ast, expr.module), FlatAst.get(ast, expr.function)} do
      {{:literal, Phoenix.LiveData.Tracked.Dummy}, {:literal, :keyed_stub}} ->
        [key_expr, value_expr] = expr.args

        :ok = state_static_add_dependencies(state, [key_expr])
        :ok = state_static_set_key(state, static_id, key_expr)

        rewrite_make_structure_rec(value_expr, ast, static_id, state)

      {{:literal, Phoenix.LiveData.Tracked.Dummy}, {:literal, :track_stub}} ->
        [call_expr_id] = expr.args
        _call_expr = %Expr.CallMF{} = FlatAst.get(ast, call_expr_id)

        :ok = state_static_add_dependencies(state, [call_expr_id])

        state_static_add_slot(state, static_id, call_expr_id)

      _ ->
        :ok = state_static_add_dependencies(state, [expr_id])
        state_static_add_slot(state, static_id, expr_id)
    end
  end

  def rewrite_make_structure_rec(%Expr.MakeMap{prev: nil} = expr, _expr_id, ast, static_id, state) do
    kvs_static =
      Enum.map(expr.kvs, fn {key, val} ->
        key_rewrite = rewrite_make_structure_rec(key, ast, static_id, state)
        val_rewrite = rewrite_make_structure_rec(val, ast, static_id, state)

        {key_rewrite, val_rewrite}
      end)

    {:make_map, nil, kvs_static}
  end

  def rewrite_make_structure_rec(%Expr.MakeTuple{elements: elems}, _expr_id, ast, static_id, state) do
    elems_static = Enum.map(elems, &rewrite_make_structure_rec(
          &1, ast, static_id, state))

    {:make_tuple, elems_static}
  end

  def rewrite_make_structure_rec({:literal, lit}, _expr_id, _ast, _static_id, _state) do
    {:literal, lit}
  end

  def rewrite_make_structure_rec(%Expr.MakeCons{} = expr, _expr_id, ast, static_id, state) do
    head_rewrite = rewrite_make_structure_rec(expr.head, ast, static_id, state)
    tail_rewrite = rewrite_make_structure_rec(expr.tail, ast, static_id, state)

    [head_rewrite | tail_rewrite]
  end

  def rewrite_make_structure_rec(expr, expr_id, _ast, static_id, state) do
    :ok = state_static_add_dependencies(state, [expr_id])
    state_static_add_slot(state, static_id, expr_id)
  end

  @doc """
  Second pass of rewriting.

  Given a set of initial nodes, will collect a set of all cumulative
  dependencies these involves.

  This has the effect of doing dead code elimination, and duplicating any
  expressions that are used in both the return value position and regular value
  positions.
  """
  def expand_dependencies(to_visit, data, ast) do
    to_visit_tuples = Enum.map(to_visit, &{false, &1})
    original = MapSet.new(to_visit)
    expand_dependencies_inner(to_visit_tuples, original, MapSet.new(), data, ast)
  end

  def expand_dependencies_inner([{_, nil} | tail], original, visited, data, ast) do
    expand_dependencies_inner(tail, original, visited, data, ast)
  end

  def expand_dependencies_inner([{from_child, expr_id} | tail], original, visited, data, ast) do
    if MapSet.member?(visited, expr_id) do
      expand_dependencies_inner(tail, original, visited, data, ast)
    else
      expr = FlatAst.get(ast, expr_id)

      case {from_child, expr} do
        {_, %Expr.Var{ref_expr: ref_expr}} ->
          visited = MapSet.put(visited, expr_id)
          item = process_expr_id(ref_expr, expr_id, data)
          expand_dependencies_inner([item | tail], original, visited, data, ast)

        {true, %Expr.Scope{}} ->
          raise "unreachable"

        {false, %Expr.Scope{exprs: exprs}} ->
          last =
            List.last(exprs)
            |> process_expr_id(expr_id, data)

          expand_dependencies_inner([last | tail], original, visited, data, ast)

        {true, _expr} ->
          children =
            expr
            |> child_exprs_without_traversed()
            |> Enum.map(&process_expr_id(&1, expr_id, data))

          expand_dependencies_inner(children ++ tail, original, visited, data, ast)

        {false, _expr} ->
          visited = MapSet.put(visited, expr_id)

          children =
            Util.child_exprs(expr)
            |> Enum.map(&process_expr_id(&1, expr_id, data))

          expand_dependencies_inner(children ++ tail, original, visited, data, ast)
      end
    end
  end

  def expand_dependencies_inner([], _original, visited, _data, _ast) do
    visited
  end

  def child_exprs_without_traversed(%Expr.Case{} = expr) do
    [expr.value]
  end

  def child_exprs_without_traversed(%Expr.For{} = expr) do
    %{expr | inner: nil}
    |> Util.child_exprs()
    |> Enum.filter(&(&1 != nil))
  end

  def child_exprs_without_traversed(%Expr.Fn{}) do
    []
  end

  def process_expr_id({:expr_bind, eid, _selector}, {:expr, _eid} = parent, data) do
    ref_expr_id = {:expr, eid}

    if MapSet.member?(data.nesting_set, {ref_expr_id, parent}) do
      {true, ref_expr_id}
    else
      {false, ref_expr_id}
    end
  end

  def process_expr_id({:expr, _eid} = expr_id, _parent, _data) do
    {false, expr_id}
  end

  def process_expr_id({:literal, _lit_id} = expr_id, _parent, _data) do
    {false, expr_id}
  end

  @doc """
  Third pass of rewriting.

  This will take the data collected in the two first passes, and perform the
  actual rewriting.
  """
  def rewrite_scope(expr_id, data, rewritten, transcribed, out) do
    %Expr.Scope{exprs: scope_exprs} = FlatAst.get(data.ast, expr_id)
    old_rewritten = rewritten

    # Step 1: Transcribe dependencies
    {transcribed_exprs, transcribed} =
      scope_exprs
      |> Enum.filter(&MapSet.member?(data.dependencies, &1))
      |> Enum.map_reduce(transcribed, fn dep, map ->
        {expr, map} = Util.Transcribe.transcribe(dep, data, map, &Map.fetch!(rewritten, &1), out)
        {expr, map}
      end)

    # Step 2: Rewrite statics
    {rewritten_exprs, rewritten} =
      scope_exprs
      |> Enum.filter(&MapSet.member?(data.traversed, &1))
      |> Enum.map_reduce(rewritten, &rewrite_scope_expr(&1, data, &2, transcribed, out))

    {rewritten_result, _rewritten} = rewrite_scope_expr(expr_id, data, rewritten, transcribed, out)

    scope_exprs = Util.recursive_flatten([transcribed_exprs, rewritten_exprs, rewritten_result])

    new_expr_id = PDAst.add_expr(out, Expr.Scope.new(scope_exprs))

    {new_expr_id, old_rewritten}
  end

  def rewrite_scope_expr(expr_id, data, rewritten, transcribed, out) do
    case Map.fetch(data.statics, expr_id) do
      :error ->
        expr = FlatAst.get(data.ast, expr_id)
        rewrite_scope_expr(expr, expr_id, data, rewritten, transcribed, out)

      {:ok, {:unfinished, _ns, [_ret_expr_id], _key}} ->
        {[], rewritten}

      # Special case, the whole static is useless.
      {:ok, {:finished, %Slot{num: 0}, [_inner_expr_id], nil}} ->
        raise "unimpl"

      # rewritten = Map.put(rewritten, expr_id, inner_expr_id)
      # {inner_expr_id, rewritten}

      {:ok, {:finished, static, slots, key}} ->
        new_slots = Enum.map(slots, fn
          {:expr_bind, eid, selector} ->
            expr_id = {:expr, eid}
            {:expr, new_eid} = Map.get(rewritten, expr_id) || Map.fetch!(transcribed, expr_id)
            {:expr_bind, new_eid, selector}

          {:expr, _eid} = expr_id ->
            Map.get(rewritten, expr_id) || Map.fetch!(transcribed, expr_id)
        end)

        new_key =
          if key do
            Map.fetch!(transcribed, key)
          end

        new_expr = Expr.MakeStatic.new(expr_id, static, new_slots, data.mfa, new_key)
        new_expr_id = PDAst.add_expr(out, new_expr)
        rewritten = Map.put(rewritten, expr_id, new_expr_id)
        {new_expr_id, rewritten}
    end
  end

  def rewrite_scope_expr(expr, expr_id, data, rewritten, transcribed, out) do
    new_expr_id = PDAst.add_expr(out)
    rewritten = Map.put(rewritten, expr_id, new_expr_id)

    {new_expr, rewritten} =
      Util.transform_expr(expr, rewritten, fn kind, selector, inner, rewritten ->
        case {expr, kind, selector} do
          {%Expr.For{}, :scope, :inner} ->
            {new_inner, _rewritten} = rewrite_scope(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {%Expr.Case{}, :scope, {_idx, :body}} ->
            {new_inner, _rewritten} = rewrite_scope(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {_, :scope, _} ->
            {new_inner, _transcribed} =
              Util.Transcribe.transcribe(
                inner,
                data,
                transcribed,
                &Map.fetch!(rewritten, &1),
                out
              )

            {new_inner, rewritten}

          {_, :value, _} ->
            new_inner = rewrite_resolve(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {_, :pattern, _} ->
            {inner, rewritten}
        end
      end)

    :ok = PDAst.set_expr(out, new_expr_id, new_expr)
    rewritten = Map.put(rewritten, expr_id, new_expr_id)

    {new_expr_id, rewritten}
  end

  def rewrite_resolve({:expr_bind, eid, selector}, _data, rewritten, transcribed, _out) do
    expr_id = {:expr, eid}
    {:expr, new_eid} = Map.get(rewritten, expr_id) || Map.fetch!(transcribed, expr_id)
    {:expr_bind, new_eid, selector}
  end

  def rewrite_resolve({:expr, _eid} = expr_id, _data, rewritten, transcribed, _out) do
    Map.get(rewritten, expr_id) || Map.fetch!(transcribed, expr_id)
  end

  def rewrite_resolve({:literal, _lit_id} = literal_id, data, _rewritten, _transcribed, out) do
    {:literal, literal} = FlatAst.get(data.ast, literal_id)
    PDAst.add_literal(out, literal)
  end

  def rewrite_scope_resolve({:expr_bind, eid, selector}, _data, rewritten, _transcribed, _out) do
    expr_id = {:expr, eid}
    {:expr, new_eid} = Map.fetch!(rewritten, expr_id)
    {:expr_bind, new_eid, selector}
  end

  def rewrite_scope_resolve({:literal, _lit_id} = literal_id, data, _rewritten, _transcribed, out) do
    {:literal, literal} = FlatAst.get(data.ast, literal_id)
    PDAst.add_literal(out, literal)
  end

  # Utility functions

  def state_static_add(state, static_id) do
    :ok =
      Agent.update(state, fn state ->
        :error = Map.fetch(state.statics, static_id)
        put_in(state.statics[static_id], {:unfinished, 0, [], nil})
      end)
  end

  def state_static_add_slot(state, static_id, expr_id) do
    agent_update_with_return(state, fn state ->
      {slot_id, state} =
        get_and_update_in(state.statics[static_id], fn
          {:unfinished, next_slot_id, slots, key} ->
            {next_slot_id, {:unfinished, next_slot_id + 1, [expr_id | slots], key}}
        end)

      {%Slot{num: slot_id}, state}
    end)
  end

  def state_static_set_key(state, static_id, expr_id) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn {:unfinished, nid, slots, nil} ->
        {:unfinished, nid, slots, expr_id}
      end)
    end)
  end

  def state_static_finalize(state, static_id, static_structure) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn {:unfinished, _nid, slots, key} ->
        slots = Enum.reverse(slots)
        {:finished, static_structure, slots, key}
      end)
    end)
  end

  def state_static_set(state, static_id, val) do
    Agent.update(state, fn state ->
      put_in(state.statics[static_id], val)
    end)
  end

  def state_static_fetch(state, static_id) do
    Agent.get(state, fn %{statics: statics} -> Map.fetch(statics, static_id) end)
  end

  def state_static_add_traversed(state, expr_id) do
    Agent.update(state, fn state ->
      update_in(state.traversed, &MapSet.put(&1, expr_id))
    end)
  end

  def state_static_add_dependencies(state, exprs) do
    Agent.update(state, fn state ->
      update_in(state.dependencies, &MapSet.union(&1, MapSet.new(exprs)))
    end)
  end

  def state_io_inspect(state) do
    :ok =
      Agent.get(state, fn state ->
        IO.inspect(state)
        :ok
      end)
  end

  def agent_update_with_return(agent, fun) do
    outer = self()

    :ok =
      Agent.update(agent, fn state ->
        {return, state} = fun.(state)
        send(outer, {:"$agent_return", agent, return})
        state
      end)

    receive do
      {:"$agent_return", ^agent, return} ->
        return
    end
  end
end
