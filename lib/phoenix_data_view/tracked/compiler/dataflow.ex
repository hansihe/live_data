defmodule Phoenix.DataView.Tracked.Compiler.Dataflow do
  @moduledoc """
  Given an Elixir AST, will calculate the equivallent set of dataflow equations.
  """

  defstruct next_equation_id: 0,
            equations: %{},
            next_block_id: 0,
            blocks: %{},
            next_seq_id: 0,
            seq_ids: %{},
            argument_roots: [],
            result: nil

  def new() do
    dataflow = %__MODULE__{
      next_block_id: 1,
      blocks: %{
        0 => %{
          kind: :root
        }
      }
    }
    {{:root, 0}, dataflow}
  end

  def get_equation({:comp, id}, state) do
    Map.fetch!(state.equations, id)
  end

  # def dataflow_pattern({:"%{}", _opts, inner}, assign_id, state) do
  #
  # end

  def get_incoming({:argument, _opts, _block, nil}) do
    []
  end

  def get_incoming({:call, _opts, _block, {_fun, args}}) do
    args
  end

  def get_incoming({:fetch_map, _opts, _block, {map, static_field}}) when is_atom(static_field) do
    [map]
  end

  def get_incoming({:iter, _opts, _loop, value}) do
    [value]
  end

  def get_incoming({:make_map, _opts, _block, {nil, kvs}}) do
    Enum.flat_map(kvs, fn {k, v} -> [k, v] end)
  end

  def get_incoming({:literal, _opts, _block, {_typ, _value}}) do
    []
  end

  def get_incoming({:collect_list, _opts, _loop, value}) do
    [value]
  end

  def get_incoming({:match_join, _opts, _loop, clauses}) do
    clauses
  end

  def get_incoming({:construct_static, _opts, _block, {_static_id, slots}}) do
    slots
  end

  def make_seq_id(state) do
    seq_id = state.next_seq_id

    state = %{
      state
      | next_seq_id: seq_id + 1
    }

    {seq_id, state}
  end

  def put_block(block, state) do
    id = state.next_block_id
    blocks = Map.put(state.blocks, id, block)
    state = %{state | blocks: blocks, next_block_id: id + 1}
    {id, state}
  end

  def put_match(parent_block, state) do
    {seq_id, state} = make_seq_id(state)

    initial = %{
      kind: :match,
      parent: parent_block,
      seq_id: seq_id,

      clauses: [],
      arguments: [],
      joiner: nil
    }

    {id, state} = put_block(initial, state)
    full_id = {:match, id}

    #state = push_scope(full_id, state)

    {full_id, state}
  end

  def put_match_argument({:match, match_id}, {:comp, _cid} = comp, state) do
    update_in(state.blocks[match_id].arguments, fn arguments -> [comp | arguments] end)
  end

  def put_match_clause({:match, match_id} = parent_block, state) do
    {seq_id, state} = make_seq_id(state)

    initial = %{
      kind: :match_clause,
      parent: parent_block,
      seq_id: seq_id,
      result: nil,
    }

    {id, state} = put_block(initial, state)
    full_id = {:match_clause, id}

    state = update_in(state.blocks[match_id].clauses, fn prev -> [full_id | prev] end)

    #state = push_scope(full_id, state)

    {full_id, state}
  end

  def put_match_body({:match_clause, match_id} = parent_block, state) do
    {seq_id, state} = make_seq_id(state)

    initial = %{
      kind: :match_body,
      parent: parent_block,
      seq_id: seq_id,
      result: nil,
    }

    {id, state} = put_block(initial, state)
    full_id = {:match_body, id}

    #state = push_scope(full_id, state)

    {full_id, state}
  end

  def put_match_clause_comp({:match, match_id}, {:comp, _cid} = comp, state) do
    update_in(state.blocks[match_id].clauses, fn [head | tail] -> [[comp | head] | tail] end)
  end

  def put_match_joiner({:match, match_id}, {:comp, _cid} = comp, state) do
    update_in(state.blocks[match_id].joiner, fn nil -> comp end)
  end

  def put_loop(parent_block, loop_opts \\ [], state) do
    {seq_id, state} = make_seq_id(state)

    initial = %{
      kind: :loop,
      parent: parent_block,
      seq_id: seq_id,

      opts: loop_opts,
      loopers: [],
      reducers: [],
      collectors: [],
      filters: []
    }

    {id, state} = put_block(initial, state)
    full_id = {:loop, id}

    #state = push_scope(full_id, state)

    {full_id, state}
  end

  def put_loop_looper({:loop, loop_id}, {:comp, _cid} = comp, state) do
    update_in(state.blocks[loop_id].loopers, fn loopers -> [comp | loopers] end)
  end

  def put_loop_collector({:loop, loop_id}, {:comp, _cid} = comp, state) do
    update_in(state.blocks[loop_id].collectors, fn collectors -> [comp | collectors] end)
  end

  def put_loop_filter({:loop, loop_id}, {:comp, _cid} = comp, state) do
    update_in(state.blocks[loop_id].filters, fn filters -> [comp | filters] end)
  end

  def put_loop_body({:loop, _loop_id} = parent_block, opts, state) do
    {seq_id, state} = make_seq_id(state)

    initial = %{
      kind: :loop_body,
      parent: parent_block,
      seq_id: seq_id,

      opts: opts
    }

    {id, state} = put_block(initial, state)
    full_id = {:loop_body, id}

    #state = push_scope(full_id, state)

    {full_id, state}
  end

  def put_argument(block, state) do
    {eq_id, state} = put_equation(:argument, [], block, nil, state)
    state = %{
      state |
      argument_roots: [eq_id | state.argument_roots]
    }
    {eq_id, state}
  end

  def put_equation(kind, opts, block, args, state) do
    id = state.next_equation_id
    full_id = {:comp, id}

    {seq_id, state} = make_seq_id(state)

    equations = Map.put(state.equations, id, {kind, opts, block, args})

    state = %{
      state
      | equations: equations,
        next_equation_id: id + 1,
        seq_ids: Map.put(state.seq_ids, full_id, seq_id)
    }

    {full_id, state}
  end

  def update_equation(%__MODULE__{} = state, {:comp, id}, kind, opts, block, args) do
    %{
      state |
      equations: Map.put(state.equations, id, {kind, opts, block, args})
    }
  end

end
