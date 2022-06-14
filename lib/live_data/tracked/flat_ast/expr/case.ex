defmodule LiveData.Tracked.FlatAst.Expr.Case do
  @moduledoc false

  defstruct value: nil, location: nil, clauses: []

  defmodule Clause do
    @moduledoc false

    defstruct pattern: nil, binds: nil, guard: nil, body: nil, location: nil
  end

  def new({:expr, _eid} = expr, location) do
    %__MODULE__{
      value: expr,
      location: location
    }
  end

  def add_clause(cas, {:pattern, _peid} = pattern, binds, guard, body, location) do
    clause = %Clause{
      pattern: pattern,
      binds: binds,
      guard: guard,
      body: body,
      location: location
    }

    %{cas | clauses: [clause | cas.clauses]}
  end

  def finish(cas) do
    %{
      cas |
      clauses: Enum.reverse(cas.clauses)
    }
  end

end
