defmodule LiveData.Tracked.Tree do
  alias LiveData.Tracked.Diff
  alias LiveData.Tracked.Render

  defstruct render: Render.new(),
            diff: Diff.new()

  def new() do
    %__MODULE__{}
  end

  def render(tree, state) do
    {ops, render_state} = Render.render_diff(tree, state.render)

    {diff_ops, diff_state} = Diff.diff_ops(ops, state.diff)
    if LiveData.debug_prints?(), do: IO.inspect diff_ops

    state = %{
      state |
      render: render_state,
      diff: diff_state
    }

    {ops, state}
  end

end
