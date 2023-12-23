defmodule LiveData.Tracked.Encoding.JSON do
  alias LiveData.Tracked.Tree
  alias LiveData.Tracked.Aliases

  @op_render 0
  @op_set_fragment 1
  @op_set_fragment_root_template 2
  @op_patch_fragment 3
  @op_set_template 4
  #@op_reset 5

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
  def escape_fragment("$f", state), do: {["$e", "$f"], state}
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

  def escape_template({:make_binary, elements}, state) do
    {elements_escaped, state} = Enum.map_reduce(elements, state, &escape_template(&1, &2))
    {["$f" | elements_escaped], state}
  end

  def escape_template([head | tail], state) do
    {head_esc, state} = escape_template(head, state)
    {tail_esc, state} = escape_template(tail, state)

    {[head_esc | tail_esc], state}
  end
  def escape_template([], state) do
    {[], state}
  end

  def escape_template({:literal, lit}, state) do
    {lit, state}
  end

  #def read(ops) do
  #  Enum.map(ops, fn
  #    [@op_render, frag_id] ->
  #      {:render, frag_id}

  #    [@op_set_fragment, frag_id, escaped] ->
  #      unescaped = unescape_fragment(escaped)
  #      {:set_fragment, frag_id, unescaped}

  #    [@op_set_fragment_root_template, frag_id, template_id | slots] ->
  #      escaped = ["$t", template_id | slots]
  #      unescaped = unescape_fragment(escaped)
  #      {:set_fragment, frag_id, unescaped}

  #    [@op_patch_fragment, frag_id, escaped] ->
  #      unescaped = unescape_fragment(escaped)
  #      {:patch_fragment, frag_id, unescaped}

  #    [@op_set_template, temp_id, escaped] ->
  #      unescaped = unescape_template(escaped)
  #      {:set_template, temp_id, unescaped}
  #  end)
  #end

  #def unescape_fragment(["$t", id | slots]) do
  #  IO.inspect slots, label: :slots
  #  %Tree.Template{
  #    id: id,
  #    slots: Enum.map(slots, &unescape_fragment/1)
  #  }
  #end
  #def unescape_fragment(["$r", id]) do
  #  %Tree.Ref{id: id}
  #end
  ## TODO remove when complete
  #def unescape_fragment(num) when is_number(num) do
  #  num
  #end
  #def unescape_fragment(atom) when is_atom(atom) do
  #  atom
  #end

  #def unescape_template(["$s", slot_num]) do
  #  %Tree.Slot{num: slot_num}
  #end
  #def unescape_template(map) when is_map(map) do
  #  kvs = Enum.map(map, fn {key, value} ->
  #    [unescape_template(key), unescape_template(value)]
  #  end)
  #  {:make_map, nil, kvs}
  #end
  #def unescape_template([]) do
  #  {:literal, []}
  #end
  #def unescape_template(val) when is_atom(val) do
  #  {:literal, val}
  #end

end
