defmodule Phoenix.DataView.Tracked.Tree do
  alias Phoenix.DataView.Tracked.Tree
  alias Phoenix.DataView.Tracked.Diff
  alias Phoenix.DataView.Tracked.Render
  alias Phoenix.DataView.Tracked.Encoding

  defstruct render: Render.new(),
            diff: Diff.new()

  def new() do
    %__MODULE__{}
  end

  def render(tree, state) do
    {ops, render_state} = Render.render_diff(tree, state.render)

    # {ops, diff_state} = Diff.diff_ops(ops, state.diff)

    state = %{
      state |
      render: render_state,
      #diff: diff_state
    }

    {ops, state}
  end

end
