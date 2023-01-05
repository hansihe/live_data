alias LiveData.Tracked.FlatAst.Expr

defmodule LiveData.Tracked.FlatAst.Expr.MakeCons do
  @moduledoc """
  Corresponds to list cell construction in the Elixir AST. Represented as `[head | tail]`.
  """

  defstruct head: nil, tail: nil

  def new(head, tail) do
    %__MODULE__{
      head: head,
      tail: tail
    }
  end
end

defimpl Expr, for: Expr.MakeCons do

  def transform(%Expr.MakeCons{} = expr, acc, fun) do
    {new_head, acc} = fun.(:value, :head, expr.head, acc)
    {new_tail, acc} = fun.(:value, :tail, expr.tail, acc)

    new_expr = %{expr | head: new_head, tail: new_tail}
    {new_expr, acc}
  end

end
