defmodule LiveData.Tracked.FlatAst.Expr.CallMF do
  @moduledoc """
  Corresponds to a call to a `module.function(arg, ..)` in the Elixir AST.
  `module` can be either the module to call, or nil for a call to the same
  module as the function we are currently working on is defined in.
  """

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
