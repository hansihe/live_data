# LiveData

LiveData can be summarized as LiveView but for JSON data.

LiveData makes it easy to add efficient live updating or interactivity to your existing SPA or native app.

A core concept in LiveData is a tracked function, declared using `deft` instead of the regular `def`. Tracked functions make is possible to separate out static parts of your data structure at compile time, only sending them to the client once.

Values in a `deft` can also be marked with a key using `keyed`. This approach is inspired by frameworks like React, and makes it possible for the LiveData runtime to efficiently detect changes in your data without having to do an inefficient tree diff.

```elixir
defmodule DataViewDemo.SimpleData do
  use LiveData

  def mount(_params, socket) do
    {:ok, _tref} = :timer.send_after(1000, :tick)
    socket = assign(socket, :counter, 0)
    {:ok, socket}
  end

  def handle_info(:tick, socket) do
    {:ok, _tref} = :timer.send_after(1000, :tick)
    socket = assign(socket, :counter, socket.assigns.counter + 1)
    {:ok, socket}
  end
  
  # The render function is a `deft` function, and is called any 
  # time there is a change to assigns, just like in LiveView.
  #
  # The LiveData runtime takes care of efficient transmission of 
  # changes to the client.
  deft render(assigns) do
    %{
      "counter" => assigns.counter,
    }
  end
  
end

```

For an introduction to the project, you can watch this talk from ElixirConf EU 2022:

[![LiveData talk at ElixirConf EU 2022](https://img.youtube.com/vi/I4vVxtrow-E/0.jpg)](https://www.youtube.com/watch?v=I4vVxtrow-E)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `phoenix_data_view` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:data_view, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/phoenix_data_view](https://hexdocs.pm/phoenix_data_view).

