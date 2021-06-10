defmodule Phoenix.DataView.Tracked.FlatAst.Expr.CallMF do
  defstruct module: nil, function: nil, args: []

  def new(module, function, args) do
    %__MODULE__{
      module: module,
      function: function,
      args: args
    }
  end
end
