defmodule LiveData.Tracked.LanguageFeatureTest do
  use ExUnit.Case
  import LiveData.Tracked.TestHelpers

  describe "maps" do

    test "in deft" do
      module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          %{
            v: v.v,
          }
        end
      end

      value = module.__tracked__testing__(%{v: 123})

      assert value.template == {:make_map, nil,
        [{{:literal, :v}, %LiveData.Tracked.Tree.Slot{num: 0}}]}
      assert value.slots == [123]
    end

    test "priors in maps in deft not implemented" do
      {:error, _, _, _, _} = try_define_module do
        use LiveData.Tracked
        deft testing do
          %{ %{} | foo: :bar}
        end
      end
    end

    test "structs in deft not implemented" do
      {:error, _, _, _, _} = try_define_module do
        use LiveData.Tracked
        defstruct []
        deft testing do
          %__MODULE__{}
        end
      end
    end

  end

  describe "string construction" do
    test "in deft" do
      module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          "hello #{v}"
        end
      end

      value = module.__tracked__testing__("world")

      assert value.template == {:make_binary,
        [{:literal, "hello "}, %LiveData.Tracked.Tree.Slot{num: 0}]}
      assert value.slots == ["world"]
    end
  end

  describe "lists" do

    test "in deft" do
      _module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          [
            v.a,
            v.b,
            v.c,
            1
          ]
        end
      end
    end

    test "in deft with tail" do
      _module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          [
            v.a
            | v.b
          ]
        end
      end
    end

  end

  describe "matching" do

    test "basic assignment matching" do
      module = define_module! do
        use LiveData.Tracked

        deft testing(v) do
          {:ok, v1} = v
          %{foo: v1}
        end
      end

      value = module.__tracked__testing__({:ok, :yay})

      assert value.template == {:make_map, nil, [{{:literal, :foo}, %LiveData.Tracked.Tree.Slot{num: 0}}]}
      assert value.slots == [:yay]
    end

    test "function clause matching" do
      module = define_module! do
        use LiveData.Tracked

        deft testing({:one, val}) do
          {:foo, val}
        end
        deft testing({:two, val}) do
          {:bar, val}
        end
      end

      ret = module.__tracked__testing__({:one, 5})
      assert ret.template == {:make_tuple,
        [{:literal, :foo}, %LiveData.Tracked.Tree.Slot{num: 0}]}
      assert ret.slots == [5]

      ret = module.__tracked__testing__({:two, 6})
      assert ret.template == {:make_tuple,
        [{:literal, :bar}, %LiveData.Tracked.Tree.Slot{num: 0}]}
      assert ret.slots == [6]
    end

  end

  describe "anonymous function" do

    test "in deft" do
      _module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          fun = fn i -> i.o end
          fun.(v)
        end
      end
    end

  end

  describe "list comprehensions" do

    test "in deft" do
      _module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          for a <- v.v do
            {1, a}
          end
        end
      end
    end

    test "explicitly nested in deft" do
      module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          for a <- v.v do
            for b <- a.v do
              {1, b}
            end
          end
        end
      end

      assigns = %{
        v: [
          %{v: [5, 6]},
          %{v: [1, 2]}
        ]
      }

      module.__tracked__testing__(assigns)
    end

    test "implicitly nested in deft" do
      module = define_module! do
        use LiveData.Tracked
        deft testing(v) do
          for a <- v.v, b <- a.v do
            {1, b}
          end
        end
      end

      assigns = %{
        v: [
          %{v: [5, 6]},
          %{v: [1, 2]}
        ]
      }

      module.__tracked__testing__(assigns)
    end

  end

end
