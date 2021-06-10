defmodule Phoenix.DataView.Tracked.Compiler.FromAst do
  @moduledoc """
  Generates the equivalent DataFlow IR for the provided Elixir AST.
  """

  alias Phoenix.DataView.Tracked.Compiler.Dataflow

  @doc """
  Calculates the set of dataflow equations for the given AST clauses.
  """
  def from_clauses([first_clause | _] = clauses) do
    {root_block, dataflow} = Dataflow.new()

    {_opts, args, [], _body} = first_clause
    num_args = Enum.count(args)

    {arg_node_ids, dataflow} =
      Enum.map_reduce(
        Enum.take(0..num_args, num_args),
        dataflow,
        fn _arg_num, dataflow ->
          Dataflow.put_argument(root_block, dataflow)
        end
      )

    state = %{
      dataflow: dataflow,
      scope: %{},
      block: {:root, 0},
      stack: [],
    }

    {match_id, state} = push_match(state)

    state =
      update_dataflow(state, fn df ->
        Enum.reduce(df.argument_roots, df, fn arg, df ->
          Dataflow.put_match_argument(match_id, arg, df)
        end)
      end)

    {clause_returns, state} =
      Enum.map_reduce(clauses, state, fn {_opts, args, [], body}, state ->
        {match_clause_id, state} = push_match_clause(match_id, state)
        state = dataflow_clause_args(args, arg_node_ids, match_id, state)

        {match_body_id, state} = push_match_body(match_clause_id, state)
        {id, state} = dataflow_expr(body, state)

        state = pop_scope(match_body_id, state)
        state = pop_scope(match_clause_id, state)

        {id, state}
      end)

    {result_id, state} = put_equation(:match_join, [], clause_returns, state)
    state = put_match_joiner(match_id, result_id, state)

    state = pop_scope(match_id, state)

    dataflow = state.dataflow

    %{
      dataflow |
      result: result_id
    }
  end

  def dataflow_clause_args(args, node_ids, match_id, state) do
    args
    |> Enum.zip(node_ids)
    |> Enum.reduce(state, fn {arg, id}, state ->
      dataflow_pattern(arg, id, match_id, state)
    end)
  end

  def dataflow_expr({:node_id, id}, state) do
    {id, state}
  end

  def dataflow_expr(atom, state) when is_atom(atom) do
    put_equation(:literal, [], {:atom, atom}, state)
  end

  def dataflow_expr(binary, state) when is_binary(binary) do
    put_equation(:literal, [], {:binary, binary}, state)
  end

  def dataflow_expr({:for, opts, args}, state) do
    loop_opts = make_opts(opts)

    {loop_id, state} = push_loop(loop_opts, state)

    {result_id, state} =
      Enum.reduce(args, state, fn
        {:<-, opts, [pattern, expr]}, state ->
          iter_opts = make_opts(opts)

          {expr_id, state} = dataflow_expr(expr, state)

          {inner_id, state} = put_equation(:iter, iter_opts, expr_id, state)
          state = put_loop_looper(loop_id, inner_id, state)

          state = dataflow_pattern(pattern, inner_id, loop_id, state)

          state

        [{:do, body}], state ->
          collect_opts = make_opts(opts)
          {loop_body_id, state} = push_loop_body(loop_id, collect_opts, state)

          {id, state} = dataflow_expr(body, state)

          state = pop_scope(loop_body_id, state)

          {collector, state} = put_equation(:collect_list, collect_opts, id, state)
          state = put_loop_collector(loop_id, collector, state)

          {collector, state}
      end)

    state = pop_scope(loop_id, state)

    {result_id, state}
  end

  def dataflow_expr({:__block__, _opts, body}, state) do
    state = push_scope(state)

    reducer = fn entry, {_last_result, state} ->
      dataflow_expr(entry, state)
    end

    {result, state} = Enum.reduce(body, {nil, state}, reducer)

    state = pop_scope(state)

    {result, state}
  end

  def dataflow_expr({{:., _opts1, [module, function]}, opts2, args}, state)
      when is_atom(module) and is_atom(function) do
    call_opts = make_opts(opts2)

    {mapped_args, state} = Enum.map_reduce(args, state, &dataflow_expr/2)
    put_equation(:call, call_opts, {{module, function}, mapped_args}, state)
  end

  def dataflow_expr({{:., opts1, [left, right]}, _opts2, []} = expr, state)
      when is_atom(right) do
    comp_opts = make_opts(opts1)
    {left_id, state} = dataflow_expr(left, state)
    put_equation(:fetch_map, comp_opts, {left_id, right}, state)
  end

  def dataflow_expr({:=, _opts, [lhs, rhs]}, state) do
    {rhs_id, state} = dataflow_expr(rhs, state)
    state = dataflow_pattern(lhs, rhs_id, nil, state)

    {rhs_id, state}
  end

  def dataflow_expr({:%{}, _opts1, {:|, _opts2, [joiner, body]}}, state) do
    true = false
  end

  def dataflow_expr({:%{}, opts, body}, state) do
    map_opts = make_opts(opts)

    {entries, state} =
      Enum.map_reduce(body, state, fn
        {key, value}, state ->
          {key_id, state} = dataflow_expr(key, state)
          {value_id, state} = dataflow_expr(value, state)
          {{key_id, value_id}, state}
      end)

    put_equation(:make_map, map_opts, {nil, entries}, state)
  end

  def dataflow_expr({var, opts, scope}, state) when is_atom(var) and is_atom(scope) do
    counter = Keyword.get(opts, :counter)
    variable = {var, counter, scope}
    var_id = Map.fetch!(state.scope, variable)
    {var_id, state}
  end

  def dataflow_expr({callee, opts, args}, state) when is_atom(callee) and is_list(args) do
    call_opts = make_opts(opts)

    {mapped_args, state} = Enum.map_reduce(args, state, &dataflow_expr/2)
    put_equation(:call, call_opts, {callee, mapped_args}, state)
  end

  def dataflow_expr(items, state) when is_list(items) do
    reducer = fn elem, {_last_result, state} ->
      dataflow_expr(elem, state)
    end

    Enum.reduce(items, {nil, state}, reducer)
  end

  def dataflow_expr({e1, e2}, state) do
    {e1_id, state} = dataflow_expr(e1, state)
    {e2_id, state} = dataflow_expr(e2, state)
    {{e1_id, e2_id}, state}
  end

  # It doesn't ultimately matter, but we special case assignment to produce a
  # nicer set of initial dataflow equations.
  def dataflow_pattern({var, opts, scope}, rhs_id, construct, state)
      when is_atom(var) and is_atom(scope) do
    counter = Keyword.get(opts, :counter)
    variable = {var, counter, scope}
    put_variable(variable, rhs_id, state)
  end

  def dataflow_pattern(expr, rhs_id, construct, state) do
    dataflow_pattern_rec(expr, rhs_id, construct, state)
  end

  def dataflow_pattern_rec({var, opts, scope}, rhs_id, construct, state)
      when is_atom(var) and is_atom(scope) do
    counter = Keyword.get(opts, :counter)
    variable = {var, counter, scope}
    {pattern_id, state} = put_equation(:validate_pattern, [], rhs_id, state)
    state = update_dataflow(state, &Dataflow.put_match_clause_comp(construct, pattern_id, &1))
    put_variable(variable, pattern_id, state)
  end

  # ==== State Modifiers ====

  def update_dataflow(state, fun) do
    update_in(state.dataflow, fun)
  end

  def push_match(%{block: parent_block} = state) do
    {full_id, dataflow} = Dataflow.put_match(parent_block, state.dataflow)
    state = %{state | dataflow: dataflow}
    state = push_scope(full_id, state)
    {full_id, state}
  end

  def put_match_joiner(match_id, result_id, state) do
    update_dataflow(state, &Dataflow.put_match_joiner(match_id, result_id, &1))
  end

  def push_match_clause({:match, match_id}, %{block: {:match, match_id}} = state) do
    {full_id, dataflow} = Dataflow.put_match_clause(state.block, state.dataflow)
    state = %{state | dataflow: dataflow}
    state = push_scope(full_id, state)
    {full_id, state}
  end

  def push_match_body({:match_clause, match_id}, %{block: {:match_clause, match_id}} = state) do
    {full_id, dataflow} = Dataflow.put_match_body(state.block, state.dataflow)
    state = %{state | dataflow: dataflow}
    state = push_scope(full_id, state)
    {full_id, state}
  end

  def push_loop(loop_opts \\ [], state) do
    {full_id, dataflow} = Dataflow.put_loop(state.block, loop_opts, state.dataflow)
    state = %{state | dataflow: dataflow}
    state = push_scope(full_id, state)
    {full_id, state}
  end

  def put_loop_looper(loop_id, inner_id, state) do
    update_dataflow(state, &Dataflow.put_loop_looper(loop_id, inner_id, &1))
  end

  def put_loop_collector(loop_id, collector, state) do
    update_dataflow(state, &Dataflow.put_loop_collector(loop_id, collector, &1))
  end

  def push_loop_body(loop_id, loop_body_opts \\ [], %{block: loop_id} = state) do
    {full_id, dataflow} = Dataflow.put_loop_body(loop_id, loop_body_opts, state.dataflow)
    state = %{state | dataflow: dataflow}
    state = push_scope(full_id, state)
    {full_id, state}
  end

  def put_equation(kind, opts, args, state) do
    {eq_id, df} = Dataflow.put_equation(kind, opts, state.block, args, state.dataflow)
    state = %{state | dataflow: df}
    {eq_id, state}
  end

  def push_scope(block \\ nil, state)

  # We push an anonymous scope.
  def push_scope(nil, state) do
    %{
      state
      | stack: [{nil, state.scope} | state.stack]
    }
  end

  # We push a block associated scope.
  def push_scope(block, state) do
    %{
      state
      | stack: [{state.block, state.scope} | state.stack],
        block: block
    }
  end

  def pop_scope(block \\ nil, state)

  # We pop an anonymous scope. Block is unchanged.
  def pop_scope(nil, %{stack: [{nil, scope} | tail]} = state) do
    %{
      state
      | scope: scope,
        stack: tail
    }
  end

  # We pop a block associated scope. Block is popped too.
  def pop_scope(curr, %{stack: [{block, scope} | tail], block: curr} = state) when block != nil do
    %{
      state
      | scope: scope,
        block: block,
        stack: tail
    }
  end

  def put_variable({_var, _counter, _scope} = variable, id, state) do
    %{
      state
      | scope: Map.put(state.scope, variable, id)
    }
  end

  def make_opts(opts) do
    []
    |> copy_opt(opts, :line)
    |> copy_opt(opts, :node_id)
  end

  def copy_opt(acc, from, name) do
    case Keyword.fetch(from, name) do
      {:ok, value} ->
        [{name, value} | acc]

      _ ->
        acc
    end
  end
end
