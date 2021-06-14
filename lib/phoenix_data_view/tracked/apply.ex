defmodule Phoenix.DataView.Tracked.Apply do
  alias Phoenix.DataView.Tracked.Tree

  defstruct templates: %{},
            fragments: %{},
            rendered: nil

  def new do
    %__MODULE__{}
  end

  def apply(ops, state) do
    Enum.reduce(ops, state, &apply_op/2)
  end

  def apply_op({:set_fragment, fragment_id, fragment}, state) do
    put_in(state.fragments[fragment_id], fragment)
  end

  def apply_op({:set_template, template_id, template}, state) do
    put_in(state.templates[template_id], template)
  end

  def apply_op({:render, fragment_id}, state) do
    rendered = render_fragment(fragment_id, state)
    %{state | rendered: rendered}
  end

  def render_fragment(fragment_id, state) do
    fragment = Map.fetch!(state.fragments, fragment_id)
    apply_refs(fragment, state)
  end

  def apply_refs(%Tree.Template{} = template, state) do
    inner_template_ctx =
      template.slots
      |> Enum.with_index()
      |> Enum.map(fn {slot, idx} -> {idx, apply_refs(slot, state)} end)
      |> Enum.into(%{})

    template_structure = Map.fetch!(state.templates, template.id)

    render_template(template_structure, inner_template_ctx, state)
  end

  def apply_refs(%Tree.Ref{} = ref, state) do
    fragment = Map.fetch!(state.fragments, ref)
    apply_refs(fragment, state)
  end

  def apply_refs(%{} = map, state) do
    map
    |> Enum.map(fn {k, v} ->
      {k, apply_refs(v, state)}
    end)
    |> Enum.into(%{})
  end

  def apply_refs(list, state) when is_list(list) do
    list
    |> Enum.map(fn val ->
      apply_refs(val, state)
    end)
  end

  def apply_refs(num, _state) when is_number(num) do
    num
  end

  def apply_refs(bin, _state) when is_binary(bin) do
    bin
  end

  def apply_refs(atom, _state) when is_atom(atom) do
    atom
  end

  def render_template(%Tree.Slot{num: num}, ctx, _state) do
    Map.fetch!(ctx, num)
  end

  def render_template({:literal, literal}, _ctx, _state) do
    literal
  end

  def render_template({:make_map, nil, kvs}, ctx, state) do
    Enum.reduce(kvs, %{}, fn {key, val}, map ->
      key_o = render_template(key, ctx, state)
      val_o = render_template(val, ctx, state)
      Map.put(map, key_o, val_o)
    end)
  end

end
