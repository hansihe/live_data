defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst.StaticsAgent do
  @moduledoc false

  alias LiveData.Tracked.Tree.Slot

  def spawn do
    Agent.start_link(fn ->
      %{statics: %{}, traversed: MapSet.new(), dependencies: MapSet.new()}
    end)
  end

  def finish(pid) do
    state = Agent.get(pid, fn state -> state end)
    :ok = Agent.stop(pid)
    {:ok, state}
  end

  def add(state, static_id) do
    :ok =
      Agent.update(state, fn state ->
        :error = Map.fetch(state.statics, static_id)
        put_in(state.statics[static_id], {:unfinished, 0, [], nil})
      end)
  end

  def add_slot(state, static_id, expr_id) do
    agent_update_with_return(state, fn state ->
      {slot_id, state} =
        get_and_update_in(state.statics[static_id], fn
          {:unfinished, next_slot_id, slots, key} ->
            {next_slot_id, {:unfinished, next_slot_id + 1, [expr_id | slots], key}}
        end)

      {%Slot{num: slot_id}, state}
    end)
  end

  def set_key(state, static_id, expr_id) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn {:unfinished, nid, slots, nil} ->
        {:unfinished, nid, slots, expr_id}
      end)
    end)
  end

  def finalize(state, static_id, static_structure) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn {:unfinished, _nid, slots, key} ->
        slots = Enum.reverse(slots)
        {:finished, static_structure, slots, key}
      end)
    end)
  end

  def set(state, static_id, val) do
    Agent.update(state, fn state ->
      put_in(state.statics[static_id], val)
    end)
  end

  def fetch(state, static_id) do
    Agent.get(state, fn %{statics: statics} -> Map.fetch(statics, static_id) end)
  end

  def add_traversed(state, expr_id) do
    Agent.update(state, fn state ->
      update_in(state.traversed, &MapSet.put(&1, expr_id))
    end)
  end

  def add_dependencies(state, exprs) do
    Agent.update(state, fn state ->
      canonical_exprs = Enum.map(exprs, fn
        nil -> nil
        {:expr, _eid} = expr_id -> expr_id
        {:expr_bind, eid, _selector} -> {:expr, eid}
      end)

      update_in(state.dependencies, &MapSet.union(&1, MapSet.new(canonical_exprs)))
    end)
  end

  def io_inspect(state) do
    :ok =
      Agent.get(state, fn state ->
        if LiveData.debug_prints?(), do: IO.inspect(state)
        :ok
      end)
  end

  defp agent_update_with_return(agent, fun) do
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
