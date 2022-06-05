defmodule Phoenix.LiveData.Tracked.Diff do
  alias Phoenix.LiveData.Tracked.Tree

  def new() do
    %{
      fragments: %{}
    }
  end

  def diff_ops(ops, state) do
    Enum.flat_map_reduce(ops, state, fn op, state ->
      diff_op(op, state)
    end)
  end

  def diff_op({:set_fragment, id, new_data} = op, state) do
    old = Map.fetch(state.fragments, id)
    state = put_in(state.fragments[id], new_data)

    case old do
      {:ok, old_data} ->
        {[op], state}

        #patches = diff_data(old_data, new_data)

        #case patches do
        #  :equal ->
        #    {[], state}

        #  _ ->
        #    ops = [
        #      {:patch_fragment, id, patches}
        #    ]
        #    {ops, state}
        #end

      _ ->
        {[op], state}
    end
  end

  def diff_op(op, state) do
    {[op], state}
  end

  def diff_data(%Tree.Template{} = old, %Tree.Template{} = new) do
    # TODO diff individual slots
    if old == new do
      :equal
    else
      [
        {:set_template, new}
      ]
    end
  end

  def diff_data(_old, %_{}) do
    throw "structs are unsupported"
  end

  def diff_data(%{} = old, %{} = new) do
    diffed = diff_keys(
      Map.keys(old),
      Map.keys(new),
      old,
      new,
      []
    )
    case diffed do
      [] -> :equal
      patches -> {:patch_map, patches}
    end
  end

  def diff_data(old, new) do
    if old == new do
      :equal
    else
      {:replace, new}
    end
  end

  #def diff_slots([], []) do
  #  []
  #end

  #def diff_slots([old | old_tail], [new | new_tail]) do
  #  diffed = diff_data(old, new)
  #end

  def diff_keys([key | lt], [key | rt], old, new, acc) do
    # When keys match, we diff the value.
    diffed =
      diff_data(
        Map.fetch!(old, key),
        Map.fetch!(new, key)
      )

    acc =
      case diffed do
        :equal ->
          acc
        {:replace, new_value} ->
          [{:replace, key, new_value} | acc]
        {:patch, patch} ->
          [{:patch, key, patch} | acc]
      end

    diff_keys(lt, rt, old, new, acc)
  end
  def diff_keys([lh | lt], [rh | _rt] = rl, old, new, acc) when lh < rh do
    # Item in old but not in new, remove key.
    acc = [{:remove, lh} | acc]
    diff_keys(lt, rl, old, new, acc)
  end
  def diff_keys([lh | _lt] = ll, [rh | rt], old, new, acc) when lh > rh do
    # Item in new but not in old, add key.
    value = Map.fetch!(new, rh)
    acc = [{:add, rh, value} | acc]
    diff_keys(ll, rt, old, new, acc)
  end
  def diff_keys([lh | lt], [], old, new, acc) do
    # Remainder case for left list, remove key.
    acc = [{:remove, lh} | acc]
    diff_keys(lt, [], old, new, acc)
  end
  def diff_keys([], [rh | rt], old, new, acc) do
    # Remainder case for right list, add key.
    value = Map.fetch!(new, rh)
    acc = [{:add, rh, value} | acc]
    diff_keys([], rt, old, new, acc)
  end
  def diff_keys([], [], _old, _new, acc) do
    # Terminal case.
    acc
  end

end
