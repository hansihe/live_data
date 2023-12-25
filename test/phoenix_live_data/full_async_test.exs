defmodule LiveData.AsyncFullTest do
  use ExUnit.Case, async: true

  import LiveData.Test

  test "testing" do
    {:ok, view, data} = live_data(LiveData.Test.AsyncTestingData)
    assert data == %{balance: "Loading..."}
    Process.sleep(1)
    assert render(view) == %{balance: 0}
  end
end
