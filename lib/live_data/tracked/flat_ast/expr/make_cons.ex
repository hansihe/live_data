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
