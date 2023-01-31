defmodule LiveData.Test.TestingData do
  use LiveData

  def mount(_params, socket) do
    socket = assign(socket, :counter, 0)
    {:ok, socket}
  end

  deft render(assigns) do
    %{
      counter: assigns[:counter]
    }
  end

  def handle_info(:increment, socket) do
    socket = assign(socket, :counter, socket.assigns.counter + 1)
    {:ok, socket}
  end

  def handle_event("increment", socket) do
    socket = assign(socket, :counter, socket.assigns.counter + 1)
    {:ok, socket}
  end

end
