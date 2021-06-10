defmodule Phoenix.DataView.Tracked.FlatAst.Expr.Literal do
  defstruct literal: nil

  def new(literal) do
    %__MODULE__{
      literal: literal
    }
  end
end
