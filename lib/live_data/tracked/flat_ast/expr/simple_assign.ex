defmodule LiveData.Tracked.FlatAst.Expr.SimpleAssign do
  @moduledoc false

  defstruct bind: nil, inner: nil

  def new(bind, inner) do
    %__MODULE__{
      bind: bind,
      inner: inner
    }
  end
end
