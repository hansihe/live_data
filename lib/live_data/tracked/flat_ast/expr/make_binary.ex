alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.MakeBinary do
  @moduledoc """
  Corresponds to binary construction in the Elixir AST. Represented as `{:<<>>, _, elems}`.
  """

  defstruct components: [], location: nil

  def new(components, location) do
    %__MODULE__{
      components: components,
      location: location
    }
  end
end

defimpl Expr, for: Expr.MakeBinary do
  def transform(%Expr.MakeBinary{} = expr, acc, fun) do
    # TODO size specifier
    {new_components, acc} =
      expr.components
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {{elem, specifiers}, idx}, acc ->
        {new_elem, acc} = fun.(:value, idx, elem, acc)
        {{new_elem, specifiers}, acc}
      end)

    new_expr = %{expr | components: new_components}
    {new_expr, acc}
  end

  def location(%Expr.MakeBinary{location: loc}) do
    loc
  end
end
