defmodule LiveData.FullTest do
  use ExUnit.Case

  #import Phoenix.ChannelTest
  #import Phoenix.ConnTest
  import LiveData.Test

  #@endpoint LiveData.Test.Endpoint

  #setup_all do
  #  LiveData.Test.Endpoint.start_endpoint(@endpoint)
  #  :ok
  #end

  #setup config do
  #  {:ok, conn: Plug.Test.init_test_session(build_conn(), config[:session] || %{})}
  #end

  test "testing" do
    {:ok, view, data} = live_data(LiveData.Test.TestingData)
    assert data == %{counter: 0}

    send view.pid, :increment
    assert render(view) == %{counter: 1}

    assert render_client_event(view, "increment") == %{counter: 2}
  end

end
