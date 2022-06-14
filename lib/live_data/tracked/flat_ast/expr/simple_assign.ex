defmodule LiveData.Tracked.FlatAst.Expr.SimpleAssign do
  @moduledoc false

  defstruct inner: nil

  def new(inner) do
    %__MODULE__{
      inner: inner
    }
  end
end
