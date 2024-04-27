defmodule LiveData.Tracked.RenderTree.LifecycleHook do
  @moduledoc """
  Enables hooking into the lifecycle events of the subtree.

  Contains a module which implements the `Tracked.LifecycleHook` behaviour.
  Callbacks are invoked by the diffing engine depending on the state of the
  subtree. When a callback is invoked, this will evaluate to another `RenderTree`
  value.
  """

  defstruct id: nil, module: nil, args: []
end
