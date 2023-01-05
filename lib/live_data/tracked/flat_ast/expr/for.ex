alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.For do
  @moduledoc """
  Corresponds to `for` list comprehension in the Elixir AST. Represented as `{:for, _, specifiers}`.

  NOTE: `uniq` and `reduce` are currently not implemented, they are TODOs.
  """

  defstruct items: nil, into: nil, inner: nil, location: nil

  def new(items, into, inner, location \\ nil) do
    %__MODULE__{
      items: items,
      into: into,
      inner: inner,
      location: location
    }
  end
end

defimpl Expr, for: Expr.For do

  def transform(%Expr.For{} = expr, acc, fun) do
    {new_items, acc} =
      expr.items
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn
        {{:loop, pattern, binds, body}, idx}, acc ->
          {{new_pattern, new_binds}, acc} = fun.(:pattern, {idx, :pattern}, {pattern, binds}, acc)
          {new_body, acc} = fun.(:scope, {idx, :generator}, body, acc)
          {{:loop, new_pattern, new_binds, new_body}, acc}

        {{:filter, body}, idx}, acc ->
          {new_body, acc} = fun.(:scope, {idx, :filter}, body, acc)
          {{:filter, new_body}, acc}
      end)

    {new_into, acc} =
      if expr.into do
        fun.(:value, :into, expr.into, acc)
      else
        {nil, acc}
      end

    {new_inner, acc} = fun.(:scope, :inner, expr.inner, acc)

    new_expr = %{
      expr |
      items: new_items,
      into: new_into,
      inner: new_inner
    }
    {new_expr, acc}
  end

end
