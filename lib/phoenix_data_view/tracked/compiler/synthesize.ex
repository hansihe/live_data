defmodule Phoenix.DataView.Tracked.Compiler.Synthesize do
  @moduledoc """
  Given a computation in dataflow form, will synthesize an equivallent Elixir
  AST.
  """

  alias Phoenix.DataView.Tracked.Compiler.Dataflow
  alias Phoenix.DataView.Tracked.Compiler.Auxiliary

  def synthesize(%Auxiliary{} = aux) do
    IO.inspect(aux)
    eqs_by_block = make_block_eqs(aux)
    block_tree = make_block_tree(aux, eqs_by_block)
    IO.inspect(block_tree)

    scope =
      aux.dataflow.argument_roots
      |> Enum.map(fn {:comp, id} -> {{:comp, id}, {:argument, [counter: id], nil}} end)
      |> Enum.into(%{})

    synth_block(block_tree, scope, eqs_by_block, aux.dataflow)

    true = false
  end

  def make_block_eqs(aux) do
    aux.dataflow.equations
    |> Enum.group_by(
      fn {_id, {_kind, _opts, {_block_kind, block_id}, _args}} -> block_id end,
      fn {id, _eq} -> id end
    )
    |> Enum.map(fn {block, comps} ->
      {block, MapSet.new(comps)}
    end)
    |> Enum.into(%{})
  end

  def make_block_tree(aux, eqs_by_block) do
    %{kind: :root} = aux.dataflow.blocks[0]

    base_tree =
      Enum.reduce(aux.dataflow.blocks, %{}, fn
        {_self_id, %{kind: :root}}, map ->
          map

        {self_id, %{parent: {_kind, id}}}, map ->
          Map.update(map, id, [self_id], &[self_id | &1])
      end)

    make_block_tree_rec(0, base_tree, aux, eqs_by_block)
  end

  def make_block_tree_rec(id, base_tree, aux, eqs_by_block) do
    block = Map.fetch!(aux.dataflow.blocks, id)
    eqs = Map.get(eqs_by_block, id, MapSet.new())
    children = Map.get(base_tree, id, [])

    expanded_children =
      children
      |> Enum.map(&{&1, make_block_tree_rec(&1, base_tree, aux, eqs_by_block)})
      |> Enum.into(%{})

    forward = MapSet.new()
    reverse = MapSet.new()

    {forward, reverse} =
      Enum.reduce(expanded_children, {forward, reverse}, fn {_id, child}, {forward, reverse} ->
        {
          MapSet.union(forward, child.forward_depset),
          MapSet.union(reverse, child.reverse_depset)
        }
      end)

    {forward, reverse} =
      Enum.reduce(eqs, {forward, reverse}, fn id, {forward, reverse} ->
        {
          MapSet.union(forward, Map.fetch!(aux.forward_set, id)),
          MapSet.union(reverse, Map.fetch!(aux.reverse_set, id))
        }
      end)

    full_body = Enum.map(children, &{:block, &1}) ++ Enum.map(eqs, &{:eq, &1})

    body =
      full_body
      # The first sort is done by the seq number specified in options.
      # This ensures that order is preserved to the original code to the
      # degree which it makes sense.
      |> Enum.sort_by(fn
        {:eq, id} ->
          {_kind, opts, _block, _args} = Dataflow.get_equation({:comp, id}, aux.dataflow)
          Keyword.get(opts, :seq, nil)

        {:block, id} ->
          nil
      end)
      # The second sort is done by explicit data dependencies.
      # Since the sort implementation is stable, order should be preserved
      # as long as there is no dependency issues.
      # In the case that there are issues (probably introduced by passes
      # rewriting the IR), these will be resolved here.
      |> Enum.sort_by(
        fn
          {:eq, id} ->
            {MapSet.new([id]), Map.fetch!(aux.forward_set, id)}

          {:block, id} ->
            block = Map.fetch!(expanded_children, id)
            {block.body, block.forward_depset}
        end,
        fn {_l_body, l_set}, {r_body, _r_set} ->
          MapSet.disjoint?(l_set, r_body)
        end
      )

    block
    |> Map.put(:children, expanded_children)
    |> Map.put(:body, eqs)
    |> Map.put(:body_order, body)
    |> Map.put(:forward_depset, forward)
    |> Map.put(:reverse_depset, reverse)
  end

  def synth_block(%{kind: :root} = block, scope, eqs_by_block, dataflow) do
    [child_id] = Map.keys(block.children)
    child_block = Map.fetch!(block.children, child_id)

    synth_block(child_block, scope, eqs_by_block, dataflow)
  end

  def synth_block(%{kind: :match, arguments: arguments} = block, scope, eqs_by_block, dataflow)
      when is_list(arguments) do
    # A match block should only contain its joiner.
    1 = MapSet.size(block.body)
    joiner = block.joiner

    ast_args = Enum.map(arguments, &Map.fetch!(scope, &1))
    ast_args_tuple = {:{}, [], ast_args}

    clauses_ast =
      Enum.map(block.clauses, fn {:match_clause, block_id} ->
        block = Map.fetch!(block.children, block_id)
        synth_block(block, scope, eqs_by_block, dataflow)
      end)

    IO.inspect(ast_args_tuple)

    # {match_items, scope} = Enum.reduce(arguments, scope, &synth_value(&1, ))

    # match_args = {:{}, [], Enum.map(arguments, &synth_value()))
    # {:case, [], }

    true = false
  end

  def synth_block(%{kind: :match_clause} = block, scope, eqs_by_block, dataflow) do
    0 = MapSet.size(block.body)
    [{:block, inner}] = block.body_order

    block = Map.fetch!(block.children, inner)
    synth_block(block, scope, eqs_by_block, dataflow)

    true = false
  end

  def synth_block(%{kind: :match_body} = block, scope, eqs_by_block, dataflow) do
    Enum.map_reduce(block.body_order, scope, fn
      {:block, block_id}, scope ->
        block = Map.fetch!(block.children, block_id)
        synth_block(block, scope, eqs_by_block, dataflow)
    end)
  end

  def synth_block(%{kind: :loop} = block, scope, eqs_by_block, dataflow) do
  end

  # def synthesize_blocks(%Dataflow{} = dataflow) do
  #  # The set of dataflow equations are flat, there is no scope or nesting.
  #  #
  #  # In order to synthesize the final AST, which contains nested and scoped
  #  # blocks, we first generate the general skeleton nesting structure to
  #  # synthesize into. We do this by grouping the equations into constructs
  #  # with explicit nesting.

  #  bodies =
  #    dataflow.loops
  #    |> Enum.map(fn {loop_id, loop} ->
  #      openers = loop.loopers
  #      terminators = Enum.concat([loop.collectors, loop.reducers])

  #      open_set =
  #        Enum.reduce(openers, MapSet.new(), fn {:comp, id}, acc ->
  #          MapSet.union(acc, Map.fetch!(dataflow.reverse_set, id))
  #        end)

  #      close_set =
  #        Enum.reduce(terminators, MapSet.new(), fn {:comp, id}, acc ->
  #          MapSet.union(acc, Map.fetch!(dataflow.forward_set, id))
  #        end)

  #      body_set = MapSet.intersection(open_set, close_set)

  #      data = %{
  #        open: open_set,
  #        close: close_set,
  #        body: body_set
  #      }

  #      {{:loop, loop_id}, data}
  #    end)
  #    |> Enum.into(%{})

  #  bodies =
  #    dataflow.matches
  #    |> Enum.map(fn {match_id, match} ->
  #      openers = match.arguments
  #      {:comp, terminator_id} = match.joiner

  #      open_set =
  #        Enum.reduce(openers, MapSet.new(), fn {:comp, id}, acc ->
  #          MapSet.union(acc, Map.fetch!(dataflow.reverse_set, id))
  #        end)

  #      close_set = Map.fetch!(dataflow.forward_set, terminator_id)

  #      body_set = MapSet.intersection(open_set, close_set)

  #      data = %{
  #        open: open_set,
  #        close: close_set,
  #        body: body_set
  #      }

  #      {{:match, match_id}, data}
  #    end)
  #    |> Enum.into(bodies)

  #  skeleton =
  #    bodies
  #    |> Enum.sort_by(fn {_k, v} -> -MapSet.size(v.body) end)
  #    |> Enum.reduce([], fn elem, acc ->
  #      make_tree(elem, acc, [])
  #    end)
  #    |> sort_tree(dataflow)

  #  IO.inspect(skeleton, label: "hierarchical skeleton")

  #  state = %{
  #    done: MapSet.new(),
  #    var_counter: 0
  #  }

  #  synth_root(skeleton, %{}, state, dataflow)

  #  true = false
  # end

  # def unique_var(name, state) when is_atom(name) do
  #  counter = state.var_counter
  #  state = %{state | var_counter: counter + 1}
  #  var = {name, [counter: counter], nil}
  #  {var, state}
  # end

  # def put_eq(bound, id, expr) do
  #  Map.put(bound, id, expr)
  # end

  # def synth_root([%{id: {:match, _}} = item], bound, state, dataflow) do
  #  {arguments, {bound, state}} =
  #    dataflow.argument_roots
  #    |> Enum.map_reduce({bound, state}, fn argument, {bound, state} ->
  #      {var, state} = unique_var(:arg, state)
  #      bound = put_eq(bound, argument, var)
  #      {var, {bound, state}}
  #    end)

  #  synth(item, bound, state, dataflow)

  #  true = false
  # end

  # def synth(%{id: {:match, match_id}} = item, bound, state, dataflow) do
  #  match = Map.fetch!(dataflow.matches, match_id)
  #  {:match_join, _opts, clause_returns} = Dataflow.get_equation(match.joiner, dataflow)

  #  {clauses, state} = Enum.reduce(clause_returns, state, fn eq, state ->

  #  end)

  #  IO.inspect clause_returns
  # end

  # def sort_tree(tree, dataflow) do
  #  tree
  #  |> Enum.sort_by(fn
  #    %{id: {:loop, loop_id}} ->
  #      Map.fetch!(dataflow.loops, loop_id)

  #    %{id: {:match, match_id}} ->
  #      Map.fetch!(dataflow.matches, match_id)
  #  end)
  #  |> Enum.map(fn entity ->
  #    sub = sort_tree(entity.sub, dataflow)
  #    %{entity | sub: sub}
  #  end)
  # end

  # def make_tree({set_id, data}, [], acc) do
  #  entity = %{
  #    id: set_id,
  #    data: data,
  #    sub: []
  #  }

  #  [entity | acc]
  # end

  # def make_tree({set_id, data}, [%{id: r_set_id, data: r_data, sub: subhier} | tail], acc) do
  #  if MapSet.subset?(data.body, r_data.body) do
  #    subhier = make_tree({set_id, data}, subhier, [])

  #    entity = %{
  #      id: r_set_id,
  #      data: r_data,
  #      sub: subhier
  #    }

  #    acc ++ [entity | tail]
  #  else
  #    0 = MapSet.size(MapSet.intersection(data.body, r_data.body))

  #    entity = %{
  #      id: r_set_id,
  #      data: r_data,
  #      sub: subhier
  #    }

  #    make_tree({set_id, data}, tail, [entity | acc])
  #  end
  # end
end
