defmodule LiveData.Test.AsyncTestingData do
  use LiveData

  def mount(_params, socket) do
    socket = assign_async(socket, :balance, fn -> {:ok, %{balance: 0}} end)
    {:ok, socket}
  end

  deft render(assigns) do
    %{
      balance:
        async_result(assigns[:balance],
          ok: fn result -> result end,
          loading: fn -> "Loading..." end,
          failed: fn result -> "Failed: #{inspect(result)}" end
        )
    }
  end
end
