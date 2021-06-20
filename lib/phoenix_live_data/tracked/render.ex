defmodule Phoenix.LiveData.Tracked.Render do
  alias Phoenix.LiveData.Tracked
  alias Phoenix.LiveData.Tracked.Tree
  alias Phoenix.LiveData.Tracked.RenderTree

  @root_id {{__MODULE__, :internal, 0}, 0}

  def new do
    %{
      generation: 0,
      fragments: %{},
      templates: %{},
      sent_templates: MapSet.new(),
      new_templates: MapSet.new(),
      previous: nil
    }
  end

  def render_diff(tree, state) do
    state = %{state | generation: state.generation + 1}

    wrapper_tree = add_root_key(tree)
    {:ok, root, state} = traverse(wrapper_tree, state, &render_prepass_mapper/2)

    %Tree.Ref{id: root_id, key: root_key} = root

    active = %{root => nil}
    active = add_active(state.fragments[root_id].values[root_key].value, active, state)
    #state = assign_aliases(active, state)

    # TODO garbage collect state

    template_set_ops =
      Enum.map(state.new_templates, fn template_id ->
        {:set_template, template_id, Map.fetch!(state.templates, template_id)}
      end)

    state = %{
      state |
      sent_templates: MapSet.union(state.sent_templates, state.new_templates),
      new_templates: MapSet.new()
    }

    fragment_set_ops =
      active
      |> Enum.map(fn {ref, nil} ->
        data = state.fragments[ref.id].values[ref.key]

        if data.changed_generation == state.generation do
          {:set_fragment, ref, data.value}
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # TODO minimize diffs

    ops = Enum.concat([
      template_set_ops,
      fragment_set_ops,
      [{:render, root}]
    ])

    {ops, state}
  end

  def get_alias(state, ref) do
    Map.fetch!(state.aliases, ref)
  end

  def add_root_key(tree) do
    %RenderTree.Keyed{
      id: @root_id,
      key: 0,
      escapes: :always,
      render: fn -> tree end
    }
  end

  #def assign_aliases(active, state) do
  #  Enum.reduce(active, state, fn {ref, nil}, state ->
  #    if Map.has_key?(state.aliases, ref) do
  #      state
  #    else
  #      %{
  #        state
  #        | aliases: Map.put(state.aliases, ref, state.next_alias),
  #          next_alias: state.next_alias + 1
  #      }
  #    end
  #  end)
  #end

  def add_active(tree, acc, state) do
    {:ok, _tree, new} = traverse(tree, %{}, &add_active_traversal_fn/2)

    merged = Map.merge(acc, new)

    Enum.reduce(new, merged, fn {ref, nil}, acc ->
      add_active(state.fragments[ref.id].values[ref.key].value, acc, state)
    end)
  end

  def add_active_traversal_fn(%Tree.Ref{} = ref, state) do
    state = Map.put(state, ref, nil)
    {:ok, nil, state}
  end

  def add_active_traversal_fn(%Tree.Template{} = template, state) do
    state =
      Enum.reduce(template.slots, state, fn slot_tree, state ->
        {:ok, _tree, state} = traverse(slot_tree, state, &add_active_traversal_fn/2)
        state
      end)
    {:ok, nil, state}
  end

  #def render_prepass_mapper(%Tree.Static{template: {:slot, 0}} = static, state) do
  #  true = false
  #end

  def render_prepass_mapper(%RenderTree.Keyed{} = keyed, state) do
    id = keyed.id

    state = update_in(state.fragments, &Map.put_new(&1, id, %{values: %{}}))

    {keyed_mfa, _scope_subid} = keyed.id

    scope = Map.fetch!(state.fragments, id)
    item = Map.get(scope.values, keyed.key)

    false = Map.get(item || %{}, :in_stack, false)

    state =
      if needs_render?(item, keyed, state.generation) do
        state =
          update_in(state.fragments[id].values[keyed.key], fn prev ->
            prev ||
              %{generation: nil}
              |> Map.put(:in_stack, true)
          end)

        {:ok, value, state} = traverse(keyed.render.(), state, &render_prepass_mapper/2)

        # TODO until we fix escapes.
        # Once this is fixed, only else branch should be required.
        if item != nil and item.value == value do
          put_in(state.fragments[id].values[keyed.key].generation, state.generation)
        else
          update_in(state.fragments[id].values[keyed.key], fn item ->
            if debug_mode?() and item.generation == state.generation and item.value != value do
              raise Tracked.KeyedException,
              mfa: keyed_mfa,
              line: nil,
              previous: item.value,
              next: value
            end

            item
            |> Map.put(:in_stack, false)
            |> Map.put(:generation, state.generation)
            |> Map.put(:changed_generation, state.generation)
            |> Map.put(:value, value)
            |> Map.put(:escapes, keyed.escapes)
          end)
        end
      else
        put_in(state.fragments[id].values[keyed.key].generation, state.generation)
      end

    ref = %Tree.Ref{
      id: id,
      key: keyed.key,
    }

    {:ok, ref, state}
  end

  def render_prepass_mapper(%RenderTree.Static{} = static, state) do
    id = static.id
    state =
      case Map.has_key?(state.templates, id) do
        true ->
          state

        false ->
          state = %{
            state |
            templates: Map.put(state.templates, id, static.template),
            new_templates: MapSet.put(state.new_templates, id)
          }

          state
      end


    {slots, state} = Enum.map_reduce(static.slots, state, fn slot, state ->
      {:ok, value, state} = traverse(slot, state, &render_prepass_mapper/2)
      {value, state}
    end)

    template = %Tree.Template{
      id: id,
      slots: slots
    }

    {:ok, template, state}
  end

  # When there is no previous item, we always need to render.
  def needs_render?(nil = _item, _keyed, _current_generation), do: true
  # Behaviour on rerender within the same generation varies depending
  # on whether this is a debug build or not.
  # * In a debug build we do a rerender here. This allows us to validate
  #   that the user is consistent in their key => value mapping, and to
  #   throw an error when they are not. This is done to avoid hard-to-find
  #   bugs when a tracked function might not behave as they expect.
  # * In a production build we assume that any inconsistencies have been
  #   figured out in the dev environment. We don't render, and just use
  #   what was rendered previously within the same generation.
  def needs_render?(%{generation: gen}, _keyed, gen) do
    debug_mode?()
  end

  def needs_render?(%{escapes: :always}, %{escapes: :always}, _gen), do: true
  # The escapes are unchanged. No need to rerender.
  def needs_render?(%{escapes: escapes}, %{escapes: escapes}, _gen), do: false
  # Otherwise, we need to render.
  def needs_render?(_item, _keyed, _gen), do: true

  #def expand(tree) do
  #  {:ok, out, nil} =
  #    traverse(tree, nil, fn
  #      %Tree.Cond{render: render}, nil ->
  #        out = expand(render.())
  #        {:ok, out, nil}

  #      %Tree.Keyed{render: render}, nil ->
  #        out = expand(render.())
  #        {:ok, out, nil}
  #    end)

  #  out
  #end

  def traverse(%Tree.Ref{} = op, state, mapper) do
    {:ok, value, state} = mapper.(op, state)
    {:ok, value, state}
  end

  def traverse(%Tree.Template{} = op, state, mapper) do
    {:ok, value, state} = mapper.(op, state)
    {:ok, value, state}
  end

  def traverse(%RenderTree.Keyed{} = op, state, mapper) do
    {:ok, value, state} = mapper.(op, state)
    {:ok, value, state}
  end

  def traverse(%RenderTree.Static{} = op, state, mapper) do
    {:ok, value, state} = mapper.(op, state)
    {:ok, value, state}
  end

  def traverse(%_{}, _state, _mapper) do
    raise ArgumentError, "structs are not supported by tracked functions"
  end

  def traverse(%{} = map, state, mapper) do
    {elems, state} =
      Enum.map_reduce(map, state, fn {key, value}, state ->
        if is_op?(key) do
          # TODO we don't even have a way to accomplish this for now, but there
          # are ways we can accomplish it. Do we even want to? Does it even make
          # sense?
          raise ArgumentError, "tracked ops may not be used directly in map keys"
        end

        {:ok, value, state} = traverse(value, state, mapper)
        {{key, value}, state}
      end)

    {:ok, Enum.into(elems, %{}), state}
  end

  def traverse(list, state, mapper) when is_list(list) do
    {list, state} =
      Enum.map_reduce(list, state, fn value, state ->
        {:ok, value, state} = traverse(value, state, mapper)
        {value, state}
      end)

    {:ok, list, state}
  end

  def traverse(tuple, state, mapper) when is_tuple(tuple) do
    {list, state} =
      tuple
      |> Tuple.to_list()
      |> Enum.map_reduce(state, fn value, state ->
        {:ok, value, state} = traverse(value, state, mapper)
        {value, state}
      end)

    {:ok, List.to_tuple(list), state}
  end

  def traverse(atom, state, _mapper) when is_atom(atom), do: {:ok, atom, state}
  def traverse(number, state, _mapper) when is_number(number), do: {:ok, number, state}
  def traverse(binary, state, _mapper) when is_binary(binary), do: {:ok, binary, state}

  def is_op?(%RenderTree.Keyed{}), do: true
  def is_op?(%RenderTree.Static{}), do: true
  def is_op?(%Tree.Ref{}), do: true
  def is_op?(%Tree.Slot{}), do: true
  def is_op?(%Tree.Template{}), do: true
  def is_op?(_value), do: false

  def debug_mode? do
    Application.get_env(:phoenix_data_view, :debug_mode, true)
  end
end
