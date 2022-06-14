defmodule LiveData.Socket do
  @moduledoc false

  defstruct endpoint: nil,
            transport_pid: nil,
            assigns: %{}

  @type assigns :: map()
end
