defmodule LiveData.Tracked.LanguageFeatureTest do
  use ExUnit.Case
  import LiveData.Tracked.TestHelpers

  # Maps

  #use LiveData.Tracked
  #deft testing do
  #  %{ %{} | foo: :bar}
  #end
      use LiveData.Tracked
      defstruct []
      deft test_struct do
        %__MODULE__{}
      end

  test "maps in deft" do
    {:ok, module} = try_define_module do
      use LiveData.Tracked
      deft testing(v) do
        %{
          v: v.v,
        }
      end
    end
  end

  test "priors in maps in deft not implemented" do
    {:error, _, _} = try_define_module do
      use LiveData.Tracked
      deft testing do
        %{ %{} | foo: :bar}
      end
    end
  end

  test "structs not implemented" do
    {:error, _, _} = try_define_module do
      use LiveData.Tracked
      defstruct []
      deft testing do
        %__MODULE__{}
      end
    end
  end

  # Maps


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
