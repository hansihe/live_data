defmodule LiveData.Tracked.RenderTree.EmbedFragment do
  @moduledoc """
  Explicitly embeds a custom fragment into the output.

  Can be used to implement and reference client side managed data structures.
  """

  defstruct fragment_id: nil
end
