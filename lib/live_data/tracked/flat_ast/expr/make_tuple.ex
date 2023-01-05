alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.MakeTuple do
  @moduledoc false

  defstruct elements: [], location: nil

  def new(elements, location \\ nil) do
    %__MODULE__{
      elements: elements,
      location: location
    }
  end
end

defimpl Expr, for: Expr.MakeTuple do

  def transform(%Expr.MakeTuple{} = expr, acc, fun) do
    {new_elems, acc} =
      expr.elements
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {elem, idx}, acc ->
        fun.(:value, idx, elem, acc)
      end)

    new_expr = %{ expr | elements: new_elems }
    {new_expr, acc}
  end

end
