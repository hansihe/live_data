alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.AccessField do
  @moduledoc """
  Corresponds to field access in the Elixir AST. Represented as `{:., _opts, [value, field]}`.
  """

  defstruct top: nil, field: nil, location: nil

  def new(top, field, location \\ nil) do
    %__MODULE__{
      top: top,
      field: field,
      location: location
    }
  end
end

defimpl Expr, for: Expr.AccessField do
  def transform(%Expr.AccessField{} = expr, acc, fun) do
    {new_top, acc} = fun.(:value, :top, expr.top, acc)
    new_expr = %{expr | top: new_top}
    {new_expr, acc}
  end

  def location(%Expr.AccessField{location: loc}) do
    loc
  end
end
