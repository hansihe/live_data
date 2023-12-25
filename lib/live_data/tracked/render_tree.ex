defmodule LiveData.Tracked.RenderTree do
  @moduledoc """
  A `RenderTree` is the direct output from a call to a tracked function.

  A `RenderTree` can be transformed into a list of operations using `Tracked.Render`.

  `RenderTree` nodes are as follows:
  * `Keyed` - Identifies the subtree with a key. Subtree evaluation is done
    conditionally by calling a render thunk.
  * `Static` - Static piece of data structure, containing a number of slots for
    dynamic values, along with the template.
  * `LifecycleHook` - Enables hooking into the lifecycle events of the subtree.
  * `EmbedFragment` - Explicitly embeds a custom fragment into the output.

  For more info on each node, see the module documentation for the node.
  """
end
