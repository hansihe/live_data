defmodule Phoenix.DataView.Tracked.Tree do
  alias Phoenix.DataView.Tracked.Tree
  alias Phoenix.DataView.Tracked.Diff
  alias Phoenix.DataView.Tracked.Render

  defstruct ids: nil,
            render: nil,
            diff: Diff.new()

  def new() do
    %__MODULE__{
      #ids: ids
    }
  end

  def render(tree, state) do
    {ops, render_state} =
      case state.render do
        nil ->
          Render.render_initial(tree, state.ids)
        state ->
          Render.render_diff(tree, state)
      end

    # {ops, diff_state} = Diff.diff_ops(ops, state.diff)

    state = %{
      state |
      render: render_state,
      #diff: diff_state
    }

    ops = format_ops(ops, state)

    {ops, state}
  end

  def format_ops(ops, state) do
    Enum.map(ops, fn op ->
      format_op(op, state)
    end)
  end

  def format_op({:s, ref, data}, state) do
    id = Render.get_alias(state.render, ref)
    escaped = escape_fragment(data, state)
    [:s, id, escaped]
  end

  def format_op({:f, ref}, state) do
    id = Render.get_alias(state.render, ref)
    [:f, id]
  end

  def format_op({:p, ref, patch}, state) do
    id = Render.get_alias(state.render, ref)
    escaped = format_patch(patch, state)
    [:p, id, escaped]
  end

  def format_op({:r}, state) do
    [:r]
  end

  def format_patch(:abc, state) do
    true = false
  end

  def escape_fragment(%Tree.Ref{} = ref, state) do
    ["$r", Render.get_alias(state.render, ref)]
  end

  def escape_fragment(%_{}, _state) do
    raise "unreachable"
  end

  def escape_fragment(%{} = map, state) do
    map
    |> Enum.map(fn {k, v} ->
      {k, escape_fragment(v, state)}
    end)
    |> Enum.into(%{})
  end

  def escape_fragment(list, state) when is_list(list) do
    Enum.map(list, fn value -> escape_fragment(value, state) end)
  end

  def escape_fragment(atom, _mapper) when is_atom(atom), do: atom
  def escape_fragment(number, _mapper) when is_number(number), do: number
  def escape_fragment("$e", _mapper), do: ["$e", "$e"]
  def escape_fragment("$r", _mapper), do: ["$e", "$r"]
  def escape_fragment(binary, _mapper) when is_binary(binary), do: binary

end
