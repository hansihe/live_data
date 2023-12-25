alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.Fn do
  @moduledoc """
  Corresponds to several things in the Elixir AST:
  * A `fn -> _ end` construct, represented as `{:fn, _, clauses}`.
  * The root of a `def`/`defp`. This is special-cased in the Elixir AST.
  """

  defstruct arity: nil, clauses: [], location: nil

  defmodule Clause do
    @moduledoc false

    defstruct patterns: nil, binds: nil, guard: nil, body: nil, location: nil
  end

  def new(arity, location \\ nil) do
    %__MODULE__{
      arity: arity,
      location: location
    }
  end

  def add_clause(defa, patterns, binds, guard, body, location \\ nil) do
    num_patterns = Enum.count(patterns)
    ^num_patterns = defa.arity
    :ok = Enum.each(patterns, fn {:pattern, _a} -> :ok end)

    clause = %Clause{
      patterns: patterns,
      binds: binds,
      guard: guard,
      body: body,
      location: location
    }

    %{defa | clauses: [clause | defa.clauses]}
  end

  def finish(defa) do
    %{
      defa |
      clauses: Enum.reverse(defa.clauses)
    }
  end

end

defimpl Expr, for: Expr.Fn do

  def transform(%Expr.Fn{} = expr, acc, fun) do
    {clauses, acc} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn
        {%Expr.Fn.Clause{} = clause, idx}, acc ->
          {new_patterns, acc} = fun.(:pattern, {idx, :pattern}, clause.patterns, acc)

          {new_binds, acc} = Enum.reduce(clause.binds, {[], acc}, fn bind, {list, acc} ->
            {new, acc} = fun.(:bind, {idx, :pattern}, bind, acc)
            {[new | list], acc}
          end)

          {new_guard, acc} =
            if clause.guard do
              fun.(:scope, {idx, :guard}, clause.guard, acc)
            else
              {nil, acc}
            end

          {new_body, acc} = fun.(:scope, {idx, :body}, clause.body, acc)

          {%{clause | patterns: new_patterns, binds: MapSet.new(new_binds), guard: new_guard, body: new_body}, acc}
      end)

    new_expr = %{expr | clauses: clauses}
    {new_expr, acc}
  end

end
