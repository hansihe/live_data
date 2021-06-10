defmodule Phoenix.DataView.Tracked.Compiler.ExtractStatic do

  alias Phoenix.DataView.Tracked.Compiler.Dataflow

  def extract_static(%Dataflow{} = dataflow) do
    state = %{
      dataflow: dataflow,

      rewritten: %{},

      next_static_id: 0,
      statics: %{},
    }

    {comp, state} = do_traverse(dataflow.result, state)

    {state.statics, %{state.dataflow | result: comp}}
  end

  def do_traverse({:comp, _id} = comp, %{rewritten: rewritten} = state) when is_map_key(rewritten, comp) do
    new = Map.fetch!(rewritten, comp)
    {new, state}
  end

  def do_traverse({:comp, _id} = comp, state) do
    {new_comp, state} =
      case Dataflow.get_equation(comp, state.dataflow) do
        {:match_join, opts, block, clauses} ->
          {clauses, state} = Enum.map_reduce(clauses, state, &do_traverse/2)
          dataflow = Dataflow.update_equation(
            state.dataflow, comp, :match_join, opts, block, clauses)
          state = %{state | dataflow: dataflow}
          {comp, state}

        {:call, opts, block, {{Phoenix.DataView.Tracked.Dummy, :keyed_stub} = fun, [key, value]}} ->
          {new_value, state} = do_traverse(value, state)

          dataflow = Dataflow.update_equation(
            state.dataflow, comp, :call, opts, block, {fun, [key, new_value]})
          state = %{state | dataflow: dataflow}

          {comp, state}

        {:call, opts, block, {{Phoenix.DataView.Tracked.Dummy, :track_stub} = fun, [inner_call]}} ->
          # TODO
          {comp, state}

        {:make_map, _opts, _block, _args} ->
          do_statics(comp, state)

        {:collect_list, opts, block, inner} ->
          {new_inner, state} = do_traverse(inner, state)

          dataflow = Dataflow.update_equation(
            state.dataflow, comp, :collect_list, opts, block, new_inner)
          state = %{state | dataflow: dataflow}

          {comp, state}
      end

    state = %{state | rewritten: Map.put(state.rewritten, comp, new_comp)}
    {new_comp, state}
  end

  def do_statics({:comp, _id} = comp, state) do
    {_kind, opts, block, _args} = Dataflow.get_equation(comp, state.dataflow)

    {structure, _nsid, slots, state} = do_statics_rec(comp, 0, [], state)
    slots = Enum.reverse(slots)

    static_id = state.next_static_id
    {new_comp, dataflow} = Dataflow.put_equation(:construct_static, opts, block, {static_id, slots}, state.dataflow)

    state = %{
      state |
      dataflow: dataflow,
      next_static_id: static_id + 1,
      statics: Map.put(state.statics, static_id, structure)
    }

    {new_comp, state}
  end

  def do_statics_rec({:comp, _id} = comp, next_slot_id, slots, state) do
    case Dataflow.get_equation(comp, state.dataflow) do
      {:literal, _opts, _block, value} ->
        {value, next_slot_id, slots, state}

      {:make_map, _opts, _block, {nil, values}} ->
        {map_items, next_slot_id, slots, state} =
          Enum.reduce(values, {[], next_slot_id, slots, state}, fn {key, value}, {map_items, next_slot_id, slots, state} ->
            {key_structure, next_slot_id, slots, state} = do_statics_rec(key, next_slot_id, slots, state)
            {value_structure, next_slot_id, slots, state} = do_statics_rec(value, next_slot_id, slots, state)

            map_items = [
              {key_structure, value_structure}
              | map_items
            ]

            {map_items, next_slot_id, slots, state}
          end)

        {{:map, map_items}, next_slot_id, slots, state}

      _ ->
        {new_comp, state} = do_traverse(comp, state)
        {{:slot, next_slot_id}, next_slot_id + 1, [new_comp | slots], state}
    end
  end

end
