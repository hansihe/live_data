defmodule LiveData.Tracked.LanguageFeatureTest do
  use ExUnit.Case
  import LiveData.Tracked.TestHelpers

  # Maps

  test "maps in deft" do
    module = define_module! do
      use LiveData.Tracked
      deft testing(v) do
        %{
          v: v.v,
        }
      end
    end
  end

  test "priors in maps in deft not implemented" do
    {:error, _, _, _, _} = try_define_module do
      use LiveData.Tracked
      deft testing do
        %{ %{} | foo: :bar}
      end
    end
  end

  test "structs not implemented" do
    {:error, _, _, _, _} = try_define_module do
      use LiveData.Tracked
      defstruct []
      deft testing do
        %__MODULE__{}
      end
    end
  end

  # Matching

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


  #deft map do

  #end

  # Priors in maps are unimplemented.
  #deft map_with_prior do
  #  %{ %{bar: :bar} |
  #    foo: :foo,
  #    bar: :baz,
  #  }
  #end

end
