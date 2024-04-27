alias LiveData.Tracked.FlatAst.Expr

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

defimpl Expr, for: Expr.CallMF do
  def transform(%Expr.CallMF{} = expr, acc, fun) do
    {new_module, acc} =
      if expr.module do
        fun.(:value, :mod, expr.module, acc)
      else
        {nil, acc}
      end

    {new_function, acc} = fun.(:value, :fun, expr.function, acc)

    {new_args, acc} =
      expr.args
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {arg, idx}, acc ->
        fun.(:value, {:arg, idx}, arg, acc)
      end)

    new_expr = %{
      expr
      | module: new_module,
        function: new_function,
        args: new_args
    }

    {new_expr, acc}
  end

  def location(%Expr.CallMF{location: loc}) do
    loc
  end
end
