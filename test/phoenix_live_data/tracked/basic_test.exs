defmodule LiveData.Tracked.BasicTest do
  use ExUnit.Case
  import LiveData.Tracked.TestHelpers

  use LiveData.Tracked

  require LiveData

  def blackbox(value), do: value

  deft foobar() do
    yay = keyed 1, 1
    blackbox(yay)
  end

  test "fully static data structure" do
    {:ok, module} = try_define_module do
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
    end

    out = %LiveData.Tracked.RenderTree.Static{} = module.__tracked__fully_static_data_structure__()

    assert out.slots == []

    assert out.template ==
             {:make_map, nil,
              [
                {{:literal, "a"}, {:literal, "b"}},
                {{:literal, :a}, {:literal, :b}},
                {{:literal, 1}, {:literal, 2}},
                {{:literal, :foo},
                 {:make_map, nil,
                  [{{:literal, 1}, {:literal, 2}}, {{:literal, 3}, {:literal, 4}}]}},
                {{:literal, :bar}, {:make_tuple, [literal: 1, literal: 2, literal: 3]}}
              ]}
  end

  test "with atom case" do
    {:ok, module} = try_define_module do
      use LiveData.Tracked

      deft with_atom_case(assigns) do
        case assigns[:foo] do
          :bar -> 1
          :baz -> 2
        end
      end
    end

    out = %LiveData.Tracked.RenderTree.Static{} = module.__tracked__with_atom_case__(%{:foo => :bar})
    assert out.slots == []
    assert out.template == {:literal, 1}

    out = %LiveData.Tracked.RenderTree.Static{} = module.__tracked__with_atom_case__(%{:foo => :baz})
    assert out.slots == []
    assert out.template == {:literal, 2}

    assert_raise CaseClauseError, fn -> module.__tracked__with_atom_case__(%{}) end
  end

  test "basic list comprehension" do
    {:ok, module} = try_define_module do
      use LiveData.Tracked

      deft with_basic_list_comprehension(assigns) do
        for item <- assigns[:items] do
          %{
            yay: item,
          }
        end
      end
    end

    assigns = %{:items => [:a, :b, :c]}
    [first | _tail] = module.__tracked__with_basic_list_comprehension__(assigns)

    %LiveData.Tracked.RenderTree.Static{} = first
    assert first.slots == [:a]

    assert first.template ==
             {:make_map, nil, [{{:literal, :yay}, %LiveData.Tracked.Tree.Slot{num: 0}}]}
  end


  test "with binary interpolation" do
    {:ok, module} = try_define_module do
      use LiveData.Tracked

      deft with_binary_interpolation(assigns) do
        """
        abc
        #{assigns[:a]}
        def
        """
      end
    end

    assigns = %{:a => "foobar"}
    value = module.__tracked__with_binary_interpolation__(assigns)
    #IO.inspect value
  end
end
