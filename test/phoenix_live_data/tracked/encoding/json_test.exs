defmodule LiveData.Tracked.Encoding.JsonTest do
  use ExUnit.Case

  alias LiveData.Tracked.Encoding.JSON
  alias LiveData.Tracked.FragmentTree.Slot

  describe "escape_template/2" do
    test "slot" do
      {out, _state} =
        JSON.escape_template(
          %Slot{num: 0},
          JSON.new()
        )

      assert out == ["$s", 0]
    end

    test "string formatting" do
      {out, _state} =
        JSON.escape_template(
          {:make_binary, [{:literal, "hello "}, %Slot{num: 0}]},
          JSON.new()
        )

      assert out == ["$f", "hello ", ["$s", 0]]
    end

    test "map construction" do
      {out, _state} =
        JSON.escape_template(
          {:make_map, nil,
           [
             {{:literal, "hello"}, {:literal, "world"}}
           ]},
          JSON.new()
        )

      assert out == %{"hello" => "world"}
    end

    test "list construction" do
      {out, _state} =
        JSON.escape_template(
          [{:literal, "hello"}, {:literal, "world"}],
          JSON.new()
        )

      assert out == ["hello", "world"]
    end
  end
end
