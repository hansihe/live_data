defmodule LiveData.Tracked.FlatAst.Expr.MakeCons do
  defstruct head: nil, tail: nil

  def new(head, tail) do
    %__MODULE__{
      head: head,
      tail: tail
    }
  end
end
