# Installation

## Existing projects
The instructions below will serve if you are installing the latest version
from git. To start using LiveView, add the following dependencies to your `mix.exs`
and run `mix deps.get`.

```elixir
def deps do
  [
    {:live_data, github: "hansihe/live_data"}
  ]
```

Since LiveData connections is not tied to HTTP requests, LiveData uses its
own routing system.

Create the LiveData router module in your application:

```elixir
# lib/my_app_web/data_router.ex

defmodule MyAppWeb.DataRouter do
  use LiveData.Router
end
```

Communication with LiveDatas occurs over a phoenix socket. Add the router
module as a socket to your endpoint:

```elixir
# lib/my_app_web/endpoint.ex

defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint

  # ...

  socket "/data", MyAppWeb.DataRouter

  # ...
end
```

You are now ready to add a LiveData to your app:

```elixir
# lib/my_app_web/data/hello_data.ex

defmodule MyAppWeb.HelloData do
  use LiveData

  def mount(_params, socket) do
    {:ok, socket}
  end

  deft render(_assigns) do
    %{
      hello: "data"
    }
  end
end
```

Your newly created LiveData also needs to be added to your data router:

```elixir
# lib/my_app_web/data_router.ex

defmodule MyAppWeb.DataRouter do
  use LiveData.Router

  data "/hello_data", MyAppWeb.HelloData
end
```

You are now ready to connect to your LiveData from a LiveData client!