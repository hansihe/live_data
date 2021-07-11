defmodule Phoenix.LiveData.Tracked.Encoding.JSON do
  alias Phoenix.LiveData.Tracked.Tree
  alias Phoenix.LiveData.Tracked.Aliases

  @op_render 0
  @op_set_fragment 1
  @op_set_fragment_root_template 2
  @op_patch_fragment 3
  @op_set_template 4
  @op_reset 5

  def new do
    %{
      fragment_aliases: Aliases.new(),
      template_aliases: Aliases.new()
    }
  end

  def format(ops, state) do
    Enum.map_reduce(ops, state, &format_op(&1, &2))
  end

  def format_op({:set_fragment, ref, %Tree.Template{} = template}, state) do
    {id, state} = Map.get_and_update!(state, :fragment_aliases, &Aliases.alias_for(ref, &1))
    {["$t", template_id | slots], state} = escape_fragment(template, state)
    out = [@op_set_fragment_root_template, id, template_id | slots]
    {out, state}
  end

  def format_op({:set_fragment, ref, data}, state) do
    {id, state} = Map.get_and_update!(state, :fragment_aliases, &Aliases.alias_for(ref, &1))
    {escaped, state} = escape_fragment(data, state)
    out = [@op_set_fragment, id, escaped]
    {out, state}
  end

  def format_op({:set_template, ref, template}, state) do
    {id, state} = Map.get_and_update!(state, :template_aliases, &Aliases.alias_for(ref, &1))
    {escaped, state} = escape_template(template, state)
    out = [@op_set_template, id, escaped]
    {out, state}
  end

  def format_op({:patch_fragment, ref, patch}, state) do
    {id, state} = Map.get_and_update!(state, :fragment_aliases, &Aliases.alias_for(ref, &1))
    {escaped, state} = format_patch(patch, state)
    out = [@op_patch_fragment, id, escaped]
    {out, state}
  end

  def format_op({:render, ref}, state) do
    {id, state} = Map.get_and_update!(state, :fragment_aliases, &Aliases.alias_for(ref, &1))
    out = [@op_render, id]
    {out, state}
  end

  def format_patch(nil, _state) do
    raise "unimpl"
  end

  def escape_fragment(%Tree.Ref{} = ref, state) do
    {id, state} = Map.get_and_update!(state, :fragment_aliases, &Aliases.alias_for(ref, &1))
    out = ["$r", id]
    {out, state}
  end

  def escape_fragment(%Tree.Template{} = template, state) do
    {id, state} = Map.get_and_update!(state, :template_aliases, &Aliases.alias_for(template.id, &1))
    {escaped_slots, state} = Enum.map_reduce(template.slots, state, &escape_fragment(&1, &2))
    out = ["$t", id | escaped_slots]
    {out, state}
  end

  def escape_fragment(%_{}, _state) do
    raise "unreachable"
  end

  def escape_fragment(%{} = map, state) do
    {kvs, state} =
      Enum.map_reduce(map, state, fn {k, v}, state ->
        {v_out, state} = escape_fragment(v, state)
        {{k, v_out}, state}
      end)

    out = Enum.into(kvs, %{})
    {out, state}
  end

  def escape_fragment(list, state) when is_list(list) do
    Enum.map_reduce(list, state, &escape_fragment(&1, &2))
  end

  def escape_fragment(atom, state) when is_atom(atom), do: {atom, state}
  def escape_fragment(number, state) when is_number(number), do: {number, state}
  def escape_fragment("$e", state), do: {["$e", "$e"], state}
  def escape_fragment("$r", state), do: {["$e", "$r"], state}
  def escape_fragment("$s", state), do: {["$e", "$s"], state}
  def escape_fragment("$t", state), do: {["$e", "$t"], state}
  def escape_fragment(binary, state) when is_binary(binary), do: {binary, state}

  def escape_template(%Tree.Slot{num: slot_num}, state) do
    {["$s", slot_num], state}
  end

  def escape_template({:make_map, nil, kvs}, state) do
    all_keys_literal = Enum.all?(kvs, fn
      {{:literal, _lit}, _val} -> true
      _ -> false
    end)

    if all_keys_literal do
      {kvs_list, state} =
        Enum.map_reduce(kvs, state, fn {{:literal, key_lit}, val}, state ->
          {val_esc, state} = escape_template(val, state)
          {{key_lit, val_esc}, state}
        end)

      map = Enum.into(kvs_list, %{})

      {map, state}
    else
      raise "unimpl"
    end
  end

  def escape_template([head | tail], state) do
    {head_esc, state} = escape_template(head, state)
    {tail_esc, state} = escape_template(tail, state)

    {[head_esc | tail_esc], state}
  end

  def escape_template({:literal, lit}, state) do
    {lit, state}
  end

end
