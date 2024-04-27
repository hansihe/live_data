defmodule LiveData.Test.Endpoint do
  use Phoenix.Endpoint, otp_app: :live_data

  defoverridable config: 1, config: 2

  socket("/data", LiveData.Test.DataRouter,
    websocket: true,
    longpoll: true
  )

  # def config(:pubsub_server), do: nil
  ## def config(arg, default) do
  ##  IO.inspect {arg, default}
  ##  true = false
  ## end
  ## def config(which), do: super(which)
  ## def config(which, default), do: super(which, default)
  # def config(which, default \\ nil) do
  #  IO.puts "got config #{inspect(which)}"
  #  default
  # end

  # def call(conn, _) do
  #  true = false
  # end

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  def start_endpoint(endpoint \\ __MODULE__) do
    ExUnit.CaptureLog.capture_log(fn ->
      _pid = start_supervised!(endpoint)
    end)
  end
end
