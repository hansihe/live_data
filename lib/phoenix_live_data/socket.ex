defmodule LiveData.Socket do
  defstruct endpoint: nil,
            transport_pid: nil,
            assigns: %{}

  @type assigns :: map()
end
