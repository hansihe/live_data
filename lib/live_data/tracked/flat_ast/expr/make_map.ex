alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.MakeMap do
  @moduledoc """
  Corresponds to map creation, `%{}`, in the Elixir AST. Represented as `{:%{}, _, inner}`.
  """

  defstruct struct: nil, prev: nil, kvs: [], location: nil

  def new(struct, prev, kvs, location \\ nil) do
    %__MODULE__{
      struct: struct,
      prev: prev,
      kvs: kvs,
      location: location
    }
  end
end

defimpl Expr, for: Expr.MakeMap do
  def transform(%Expr.MakeMap{} = expr, acc, fun) do
    {new_struct, acc} =
      if expr.struct do
        fun.(:value, :struct, expr.struct, acc)
      else
        {nil, acc}
      end

    {new_prev, acc} =
      if expr.prev do
        fun.(:value, :prev, expr.prev, acc)
      else
        {nil, acc}
      end

    {new_kvs, acc} =
      expr.kvs
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {{key, val}, idx}, acc ->
        {new_key, acc} = fun.(:value, {idx, :key}, key, acc)
        {new_val, acc} = fun.(:value, {idx, :val}, val, acc)
        {{new_key, new_val}, acc}
      end)

    new_expr = %{
      expr
      | struct: new_struct,
        prev: new_prev,
        kvs: new_kvs
    }

    {new_expr, acc}
  end

  def location(%Expr.MakeMap{location: loc}) do
    loc
  end
end
