defmodule Phoenix.DataView.Tracked.FlatAst.Expr.Fn do
  defstruct arity: nil, clauses: []

  def new(arity) do
    %__MODULE__{
      arity: arity
    }
  end

  def add_clause(defa, patterns, pattern_vars, {:expr, _b} = guard, {:expr, _c} = body) do
    num_patterns = Enum.count(patterns)
    ^num_patterns = defa.arity
    :ok = Enum.each(patterns, fn {:pattern, _a} -> :ok end)

    %{defa | clauses: [{patterns, pattern_vars, guard, body}]}
  end

  def add_clause(defa, patterns, pattern_vars, nil, {:expr, _c} = body) do
    num_patterns = Enum.count(patterns)
    ^num_patterns = defa.arity
    :ok = Enum.each(patterns, fn {:pattern, _a} -> :ok end)

    %{defa | clauses: [{patterns, pattern_vars, nil, body}]}
  end
end
