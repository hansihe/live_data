defmodule Phoenix.DataView.Tracked.Apply do
  defstruct root_id: nil,
            fragments: %{},
            rendered: nil

  def new do
    %__MODULE__{}
  end

  def apply(ops, state) do
    Enum.reduce(ops, state, &apply_op/2)
  end

  def apply_op([:s, fragment_id, fragment], state) do
    put_in(state.fragments[fragment_id], fragment)
  end

  def apply_op([:f, fragment_id], state) do
    %{state | root_id: fragment_id}
  end

  def apply_op([:r], state) do
    rendered = render_fragment(state.root_id, state)
    %{state | rendered: rendered}
  end

  def render_fragment(fragment_id, state) do
    fragment = Map.fetch!(state.fragments, fragment_id)
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

  def apply_refs({"$r", fragment_id}, state) do
    fragment = Map.fetch!(state.fragments, fragment_id)
    apply_refs(fragment, state)
  end

  def apply_refs({"$e", escaped}, _state) do
    escaped
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
end
