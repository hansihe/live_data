defmodule LiveData.Tracked.FlatAst.Expr.Literal do
  @moduledoc false

  defstruct literal: nil

  def new(literal) do
    %__MODULE__{
      literal: literal
    }
  end
end
