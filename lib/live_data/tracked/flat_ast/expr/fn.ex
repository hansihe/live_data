defmodule LiveData.Tracked.FlatAst.Expr.Fn do
  @moduledoc false

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

  def add_clause(defa, patterns, binds, guard, body, location \\ nil)

  def add_clause(defa, patterns, binds, {:expr, _b} = guard, {:expr, _c} = body, location) do
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

  def add_clause(defa, patterns, binds, nil, {:expr, _c} = body, location) do
    num_patterns = Enum.count(patterns)
    ^num_patterns = defa.arity
    :ok = Enum.each(patterns, fn {:pattern, _a} -> :ok end)

    clause = %Clause{
      patterns: patterns,
      binds: binds,
      guard: nil,
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
