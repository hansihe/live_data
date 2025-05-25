defmodule LiveData.Tracked.LiveViewTest do
  use ExUnit.Case

  import LiveData.Tracked.TestHelpers

  test "with liveview heex template" do
    module =
      define_module! print_trace: true do
        use LiveData.Tracked

        import LiveData.Tracked.TestHelpers, only: [sigil_H: 2]

        # <!-- <p><%= @foo %></p> -->
        deft render(assigns) do
          ~H"""
          <div>
            <p>Hello <%= @world %>!</p>
          </div>
          """
        end
      end

    ret = module.__tracked__render__(%{world: "word", foo: %{asdf: 1}})
    assert ret.template == {:make_binary, [
      {:literal, "<div>\n  <p>Hello "},
      %LiveData.Tracked.FragmentTree.Slot{num: 0},
      {:literal, "!</p>\n</div>"}
    ]}
    assert ret.slots == ["word"]
  end
end
