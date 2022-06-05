defmodule LiveData.Tracked.BasicTest do
  use ExUnit.Case

  use LiveData.Tracked

  deft fully_static_data_structure do
    %{
      "a" => "b",
      :a => :b,
      1 => 2,
      :foo => %{
        1 => 2,
        3 => 4
      },
      :bar => {1, 2, 3}
    }
  end

  test "fully static data structure" do
    out = __tracked__fully_static_data_structure__()
    assert out.slots == []
  end

end
