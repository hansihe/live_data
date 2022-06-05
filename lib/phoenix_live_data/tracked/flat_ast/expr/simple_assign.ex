defmodule LiveData.Tracked.FlatAst.Expr.SimpleAssign do
  defstruct inner: nil

  def new(inner) do
    %__MODULE__{
      inner: inner
    }
  end
end
