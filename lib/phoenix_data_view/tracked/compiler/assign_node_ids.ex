defmodule Phoenix.DataView.Tracked.Compiler.AssignNodeIds do
  def assign_node_ids([first_clause | _] = clauses) do
    {_opts, args, [], _body} = first_clause
    num_args = Enum.count(args)

    arg_node_ids = Enum.into(0..num_args, [])

    state = %{
      next_node_id: num_args
    }

    {clauses, state} = Enum.map_reduce(clauses, state, &assign_node_ids_clause/2)

    clauses
  end

  def assign_node_ids_clause({opts, args, [], body}, state) do
    {args, state} = assign_node_ids_expr(args, state)
    {body, state} = assign_node_ids_expr(body, state)

    {{opts, args, [], body}, state}
  end

  def assign_node_ids_expr(expr, state) do
    pre = fn
      bin, state when is_binary(bin) ->
        {bin, state}

      atom, state when is_atom(atom) ->
        {atom, state}

      elem, state when is_list(elem) ->
        {elem, state}

      {kind, opts, inner}, state ->
        {id, state} = next_id(state)
        {{kind, [{:node_id, id} | opts], inner}, state}

      {e1, e2}, state ->
        {{e1, e2}, state}
    end

    post = fn expr, state -> {expr, state} end

    Macro.traverse(expr, state, pre, post)
  end

  defp next_id(state) do
    id = state.next_node_id

    state = %{
      state
      | next_node_id: id + 1
    }

    {id, state}
  end
end
