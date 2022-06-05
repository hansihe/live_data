defmodule LiveData.Tracked.FlatAst.Expr.CallMF do
  defstruct module: nil, function: nil, args: [], location: nil

  def new(module, function, args, location \\ nil) do
    %__MODULE__{
      module: module,
      function: function,
      args: args,
      location: location
    }
  end
end
