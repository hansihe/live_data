defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst.StaticsAgent do
  @moduledoc """
  StaticsAgent is an agent process which collects information about statics
  during the execution of the MakeStructure subpass.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FragmentTree.Slot

  defstruct [
    statics: %{},
    # The traversed set is the set of expressions where, although they
    # where not rewritten into a static, the compiler knew how to
    # traverse them.
    # These are things like `case` or `for` where we cannot know at
    # compile-time the shape of the data.
    traversed: MapSet.new(),
    # The dependencies set is the set of expressions depended on
    # by any rewritten static.
    # Added in one of two cases:
    # * Explicitly depended on by a slot
    # * Implicitly depended on by a traversed expression
    dependencies: MapSet.new(),
  ]

  defmodule Static do
    defstruct [
      state: :unfinished,
      next_slot_id: 0,
      slots: [],
      key: nil,
      # Set when static is finalized.
      static_structure: nil,
    ]
  end

  def spawn do
    Agent.start_link(fn ->
      %__MODULE__{}
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
        put_in(state.statics[static_id], %Static{})
      end)
  end

  def add_slot(state, static_id, expr_id) do
    agent_update_with_return(state, fn state ->
      {slot_id, state} =
        get_and_update_in(state.statics[static_id], fn
          %Static{state: :unfinished} = static ->
            slot_id = static.next_slot_id
            static = %{ static |
              next_slot_id: slot_id + 1,
              slots: [expr_id | static.slots]
            }
            {slot_id, static}
        end)

      {%Slot{num: slot_id}, state}
    end)
  end

  def set_key(state, static_id, expr_id) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn
        %Static{state: :unfinished} = static ->
          %{static | key: expr_id}
      end)
    end)
  end

  def finalize(state, static_id, static_structure) do
    Agent.update(state, fn state ->
      update_in(state.statics[static_id], fn
        %Static{state: :unfinished} = static ->
          slots = Enum.reverse(static.slots)
          %{ static |
            state: :finished,
            slots: slots,
            static_structure: static_structure
          }
      end)
    end)
  end

  def set(state, static_id, %Static{} = val) do
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

  def add_dependencies(state, ast, exprs) do
    Agent.update(state, fn state ->
      canonical_exprs = Enum.map(exprs, fn
        nil -> nil
        {:expr, _eid} = expr_id -> expr_id
        {:bind, _bid} = bind_id -> FlatAst.get_bind_data(ast, bind_id).expr
        {:literal, _lid} = literal_id -> literal_id
      end)

      update_in(state.dependencies, &MapSet.union(&1, MapSet.new(canonical_exprs)))
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
