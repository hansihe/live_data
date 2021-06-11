defmodule Phoenix.DataView.Tracked.FlatAst.Pass.RewriteAst do
  @moduledoc """
  """

  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.FlatAst.Expr
  alias Phoenix.DataView.Tracked.FlatAst.PDAst
  alias Phoenix.DataView.Tracked.FlatAst.Util

  def rewrite(ast, nesting_set) do
    IO.inspect ast

    scopes =
      FlatAst.Util.traverse(ast, ast.root, %{}, fn
        id, %Expr.Scope{exprs: exprs}, scopes ->
          scopes = Map.put(scopes, id, MapSet.new(exprs))
          {:continue, scopes}

        _id, _expr, scopes ->
          {:continue, scopes}
      end)

    {:ok, out} = PDAst.init()
    new_root = PDAst.add_expr(out)
    :ok = PDAst.set_root(out, new_root)

    fn_expr = %Expr.Fn{} = FlatAst.get(ast, ast.root)

    {new_clauses, statics} =
      Enum.map_reduce(fn_expr.clauses, %{}, fn {patterns, binds, guard, body}, statics_acc ->
        new_guard =
          if guard do
            true = false
            # transcribe(guard, ast, out)
          end

        {:ok, state} =
          Agent.start_link(fn ->
            %{statics: %{}, traversed: MapSet.new(), dependencies: MapSet.new()}
          end)

        rewrite_root = rewrite_make_structure(body, ast, state)

        %{statics: statics, traversed: traversed, dependencies: dependencies} =
          Agent.get(state, fn state -> state end)

        :ok = Agent.stop(state)

        IO.inspect(rewrite_root, label: :rewrite_root)
        IO.inspect(statics, label: :statics)
        IO.inspect(traversed, label: :traversed)

        data = %{
          statics: statics,
          ast: ast,
          traversed: traversed,
          nesting_set: nesting_set
        }
        data = Map.put(data, :dependencies, expand_dependencies(MapSet.to_list(dependencies), data, ast))

        IO.inspect(dependencies, label: :dependencies_before_expansion)
        IO.inspect(data.dependencies, label: :dependencies_after_expansion)

        rewritten = %{}
        transcribed = %{ast.root => new_root}
        {new_body, _transcribed} = rewrite_scope(body, data, rewritten, transcribed, out)

        {{patterns, binds, new_guard, new_body}, Map.merge(statics_acc, statics)}
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
  def rewrite_make_structure(expr_id, key_expr \\ nil, ast, state) do
    if state_static_fetch(state, expr_id) != :error do
      expr_id
    else
      :ok = state_static_add(state, expr_id)
      static_structure = rewrite_make_structure_rec(expr_id, ast, expr_id, state)

      {:ok, static_result} = state_static_fetch(state, expr_id)
      case {static_structure, static_result} do
        {{:slot, 0}, {:unfinished, _nid, [slot_zero_expr], nil}} ->
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

  def rewrite_make_structure_rec(%Expr.Scope{exprs: exprs}, expr_id, ast, static_id, state) do
    result_expr = List.last(exprs)
    rewrite_make_structure_rec(result_expr, ast, static_id, state)
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
      {{:literal, Phoenix.DataView.Tracked.Dummy}, {:literal, :keyed_stub}} ->
        [key_expr, value_expr] = expr.args

        :ok = state_static_add_dependencies(state, [key_expr])
        :ok = state_static_set_key(state, static_id, key_expr)

        rewrite_make_structure_rec(value_expr, ast, static_id, state)

      {{:literal, Phoenix.DataView.Tracked.Dummy}, {:literal, :track_stub}} ->
        # TODO transform call

        [call_expr_id] = expr.args
        call_expr = %Expr.CallMF{} = FlatAst.get(ast, call_expr_id)

        :ok = state_static_add_dependencies(state, [call_expr_id])

        state_static_add_slot(state, static_id, call_expr_id)

      _ ->
        :ok = state_static_add_dependencies(state, [expr_id])
        state_static_add_slot(state, static_id, expr_id)
    end
  end

  def rewrite_make_structure_rec(%Expr.MakeMap{prev: nil} = expr, expr_id, ast, static_id, state) do
    #:ok = state_static_add_traversed(state, expr_id)
    # :ok = state_static_add_dependencies(state, [prev])

    kvs_static =
      Enum.map(expr.kvs, fn {key, val} ->
        key_rewrite = rewrite_make_structure_rec(key, ast, static_id, state)
        val_rewrite = rewrite_make_structure_rec(val, ast, static_id, state)

        {key_rewrite, val_rewrite}
      end)

    {:make_map, nil, kvs_static}
  end

  def rewrite_make_structure_rec({:literal, lit}, expr_id, ast, static_id, state) do
    {:literal, lit}
  end

  def rewrite_make_structure_rec(_expr, expr_id, ast, static_id, state) do
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
            |> IO.inspect()
            |> Enum.map(&process_expr_id(&1, expr_id, data))
            |> IO.inspect()

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

  def expand_dependencies_inner([], original, visited, data, _ast) do
    visited
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

    IO.inspect(scope_exprs, label: :scope_exprs)

    IO.inspect data.dependencies

    # Step 1: Transcribe dependencies
    IO.puts "BEGIN TRANSCRIBE"
    {transcribed_exprs, transcribed} =
      scope_exprs
      |> IO.inspect()
      |> Enum.filter(&MapSet.member?(data.dependencies, &1))
      |> IO.inspect()
      |> Enum.map_reduce(transcribed, fn dep, map ->
        {expr, map} = transcribe(dep, data, map, &Map.fetch!(rewritten, &1), out)
        {expr, map}
      end)
    IO.puts "END TRANSCRIBE"

    # Step 2: Rewrite statics
    {rewritten_exprs, rewritten} =
      scope_exprs
      |> Enum.filter(&MapSet.member?(data.traversed, &1))
      |> Enum.map_reduce(rewritten, &rewrite_scope_expr(&1, data, &2, transcribed, out))

    {rewritten_result, rewritten} = rewrite_scope_expr(expr_id, data, rewritten, transcribed, out)

    scope_exprs = Util.recursive_flatten([transcribed_exprs, rewritten_exprs, rewritten_result])

    new_expr_id = PDAst.add_expr(out, Expr.Scope.new(scope_exprs))
    {new_expr_id, old_rewritten}
  end

  def rewrite_scope_expr(expr_id, data, rewritten, transcribed, out) do
    IO.inspect expr_id, label: :rewrite_scope_expr

    case Map.fetch(data.statics, expr_id) do
      :error ->
        expr = FlatAst.get(data.ast, expr_id)
        rewrite_scope_expr(expr, expr_id, data, rewritten, transcribed, out)

      {:ok, {:unfinished, _ns, [ret_expr_id], _key}} ->
        # IO.inspect rewritten
        # new_ret_expr_id = Map.get(rewritten, ret_expr_id) || Map.fetch!(transcribed, ret_expr_id)
        # new_expr_id = PDAst.add_expr(out, Expr.Var.new(new_ret_expr_id))
        # {new_expr_id, rewritten}
        {[], rewritten}

        # expr = FlatAst.get(data.ast, ret_expr_id)
        # {result, rewritten} = rewrite_scope_expr(expr, ret_expr_id, data, rewritten, transcribed, out)
        # rewritten = Map.put(rewritten, expr_id, result)
        # {result, rewritten}

      {:ok, {:finished, _static, slots, key}} ->
        new_slots = Enum.map(slots, &(Map.get(rewritten, &1) || Map.fetch!(transcribed, &1)))

        new_key =
            if key do
              Map.fetch!(transcribed, key)
            end

        new_expr = Expr.MakeStatic.new(expr_id, new_slots, new_key)
        new_expr_id = PDAst.add_expr(out, new_expr)
        rewritten = Map.put(rewritten, expr_id, new_expr_id)
        {new_expr_id, rewritten}
    end
    #expr = FlatAst.get(data.ast, expr_id)
    #rewrite_scope_expr(expr, expr_id, data, rewritten, transcribed, out)
  end

  def rewrite_scope_expr(%Expr.CallMF{} = expr, expr_id, data, rewritten, transcribed, out) do
    new_module = if expr.module do
      rewrite_scope_resolve(expr.module, data, rewritten, transcribed, out)
    end

    new_function = rewrite_scope_resolve(expr.function, data, rewritten, transcribed, out)

    new_args = Enum.map(expr.args, &rewrite_scope_resolve(&1, data, rewritten, transcribed, out))

    new_expr = %Expr.CallMF{
      module: new_module,
      function: new_function,
      args: new_args
    }
    new_expr_id = PDAst.add_expr(out, new_expr)

    rewritten = Map.put(rewritten, expr_id, new_expr_id)

    {new_expr_id, rewritten}
  end

  def rewrite_scope_expr(%Expr.For{} = expr, expr_id, data, rewritten, transcribed, out) do
    new_expr_id = PDAst.add_expr(out)
    rewritten = Map.put(rewritten, expr_id, new_expr_id)

    items = Enum.map(expr.items, fn
      {:loop, pattern, binds, body} ->
        {expr, _transcribed} = transcribe(body, data, transcribed, &Map.fetch!(rewritten, &1), out)
        {:loop, pattern, binds, expr}

      {:filter, body} ->
        {expr, _transcribed} = transcribe(body, data, transcribed, &Map.fetch!(rewritten, &1), out)
        {:loop, expr}
    end)

    into = if expr.into do
      Map.fetch!(transcribed, expr.into)
    end

    {inner, _rewritten} = rewrite_scope(expr.inner, data, rewritten, transcribed, out)

    new_expr = %Expr.For{
      items: items,
      into: into,
      inner: inner
    }
    :ok = PDAst.set_expr(out, new_expr_id, new_expr)

    {new_expr_id, rewritten}
  end

  def rewrite_scope_resolve({:expr_bind, eid, selector}, data, rewritten, transcribed, out) do
    expr_id = {:expr, eid}
    {:expr, new_eid} = Map.fetch!(rewritten, expr_id)
    {:expr_bind, new_eid, selector}
  end

  def rewrite_scope_resolve({:literal, _lit_id} = literal_id, data, rewritten, transcribed, out) do
    {:literal, literal} = FlatAst.get(data.ast, literal_id)
    PDAst.add_literal(out, literal)
  end

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
          a -> IO.inspect a
          true = false
        end)

      {{:slot, slot_id}, state}
    end)
  end

  def state_static_set_key(state, static_id, expr_id) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn {:unfinished, _nid, slots, nil} ->
        {:unfinished, _nid, slots, expr_id}
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

  # def state_rewritten_fetch(state, expr_id) do
  #  Agent.get(state, fn %{rewritten: rewritten} -> Map.fetch(rewritten, expr_id) end)
  # end

  # def state_rewritten_put(state, old_expr_id, new_expr_id) do
  #  Agent.update(state, fn state ->
  #    put_in(state.rewritten, old_expr_id, new_expr_id)
  #  end)
  # end

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

  # @doc """
  # The `rewrite_traverse` function will, starting at a
  # This will traverse a single expression from the return value position, and
  # rewrite it.
  # """
  # def rewrite_traverse(expr_id, ast, state, out) do
  #  expr = FlatAst.get(ast, expr_id)

  #  new_expr = rewrite_traverse_inner(expr, expr_id, ast, state, out)

  #  id = PDAst.add_expr(out, new_expr)
  #  {:ok, id}
  # end

  # def rewrite_traverse_inner(%Expr.Scope{} = scope, scope_id, ast, state, out) do
  #  rewrite_scope(scope, scope_id, ast, state, out)
  # end

  # @doc """
  # It will perform two main actions, in order:
  # *
  # """
  # def rewrite_scope(%Expr.Scope{exprs: exprs}, scope_id, ast, state, out) do
  #  scope = MapSet.new(exprs)
  #  result_expr = List.last(exprs)

  #  true = false
  # end

  def transcribe_pattern(pat_id, data, map, out) do

  end

  #def transcribe(expr_id, data, map, backup_resolve, out) do
  #  false = Map.has_key?(map, expr_id)
  #  expr = FlatAst.get(data.ast, expr_id)

  #  {new_expr, map} = Util.transform_expr(expr, map, fn
  #    :value, _selector, expr, map ->
  #      new_var = Map.fetch!(map, expr)
  #      {new_var, map}
  #  end)
  #end

  def transcribe(expr_id, data, map, backup_resolve, out) do
    IO.inspect(expr_id, label: :transcribing)
    false = Map.has_key?(map, expr_id)
    expr = FlatAst.get(data.ast, expr_id)

    {new_expr_id, map} = transcribe(expr, expr_id, data, map, backup_resolve, out)
    map = Map.put(map, expr_id, new_expr_id)

    {new_expr_id, map}
  end

  def transcribe(%Expr.MakeMap{prev: nil} = expr, expr_id, data, map, backup_resolve, out) do
    kvs =
      Enum.map(expr.kvs, fn {key, val} ->
        new_key = transcribe(key, data, map, backup_resolve, out)
        new_val = transcribe(val, data, map, backup_resolve, out)

        {new_key, new_val}
      end)

    new_expr = %Expr.MakeMap{
      prev: nil,
      kvs: kvs
    }

    new_expr_id = PDAst.add_expr(out, new_expr)

    {new_expr_id, map}
  end

  def transcribe(%Expr.CallMF{} = expr, expr_id, data, map, backup_resolve, out) do
    module =
      if expr.module do
        transcribe_maybe_scope(expr.module, data, map, backup_resolve, out)
      end

    function = transcribe_maybe_scope(expr.function, data, map, backup_resolve, out)

    args = Enum.map(expr.args, &transcribe_maybe_scope(&1, data, map, backup_resolve, out))

    new_expr = %Expr.CallMF{
      module: module,
      function: function,
      args: args
    }

    new_expr_id = PDAst.add_expr(out, new_expr)

    {new_expr_id, map}
  end

  def transcribe(%Expr.For{} = expr, expr_id, data, map, backup_resolve, out) do
    new_expr_id = PDAst.add_expr(out)
    map = Map.put(map, expr_id, new_expr_id)
    IO.inspect map, label: :LOLWTF

    items =
      Enum.map(expr.items, fn
        {:loop, pattern, binds, body} ->
          transcribe_maybe_scope(body, data, map, backup_resolve, out)

        {:filter, body} ->
          transcribe_maybe_scope(body, data, map, backup_resolve, out)
      end)

    {into, map} =
      if expr.into do
        transcribe_maybe_scope(expr.into, data, map, backup_resolve, out)
      else
        {nil, map}
      end

    inner = transcribe_maybe_scope(expr.inner, data, map, backup_resolve, out)

    new_expr = %Expr.For{
      items: items,
      into: into,
      inner: inner
    }

    :ok = PDAst.set_expr(out, new_expr_id, new_expr)

    {new_expr_id, map}
  end

  def transcribe(%Expr.AccessField{} = expr, expr_id, data, map, backup_resolve, out) do
    new_top = transcribe_maybe_scope(expr.top, data, map, backup_resolve, out)

    new_expr = %{expr | top: new_top}
    new_expr_id = PDAst.add_expr(out, new_expr)

    {new_expr_id, map}
  end

  def transcribe(%Expr.Scope{exprs: exprs}, expr_id, data, map, backup_resolve, out) do
    {new_exprs, _map} =
      Enum.map_reduce(exprs, map, fn expr, map ->
        transcribe(expr, data, map, backup_resolve, out)
      end)

    new_expr = %Expr.Scope{exprs: new_exprs}
    new_expr_id = PDAst.add_expr(out, new_expr)

    {new_expr_id, map}
  end

  def transcribe({:expr_bind, _eid, _selector} = bind, _bind_id, data, map, backup_resolve, out) do
    new_bind = transcribe_bind(bind, map, backup_resolve)
    {new_bind, map}
  end

  def transcribe({:literal, lit}, _lit_id, data, map, backup_resolve, out) do
    new_lit_id = PDAst.add_literal(out, lit)
    {new_lit_id, map}
  end

  def transcribe_maybe_scope(expr_id, data, map, backup_resolve, out) do
    case FlatAst.get(data.ast, expr_id) do
      %Expr.Scope{} = expr ->
        IO.puts "ENTER SCOPE"
        {new_expr_id, _map} = transcribe(expr_id, data, map, backup_resolve, out)
        IO.puts "EXIT SCOPE"
        new_expr_id

      {:expr_bind, _eid, _selector} = bind ->
        transcribe_bind(bind, map, backup_resolve)

      {:literal, lit} ->
        PDAst.add_literal(out, lit)

      _ ->
        Map.fetch!(map, expr_id)
    end
  end

  def transcribe_bind({:expr_bind, eid, selector}, map, backup_resolve) do
    expr_id = {:expr, eid}
    {:expr, new_eid} = Map.get(map, expr_id) || backup_resolve.(expr_id)
    {:expr_bind, new_eid, selector}
  end
end
