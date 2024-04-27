alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.Case do
  @moduledoc """
  Corresponds to a case expression in the Elixir AST. Represented as
  `{:case, _, [value, [do: clauses]]}`.
  """

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
      cas
      | clauses: Enum.reverse(cas.clauses)
    }
  end
end

defimpl Expr, for: Expr.Case do
  def transform(%Expr.Case{} = expr, acc, fun) do
    {new_value, acc} = fun.(:value, :value, expr.value, acc)

    {clauses, acc} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn
        {%Expr.Case.Clause{} = clause, idx}, acc ->
          {{new_pattern, new_binds}, acc} =
            fun.(:pattern, {idx, :pattern}, {clause.pattern, clause.binds}, acc)

          {new_guard, acc} =
            if clause.guard do
              fun.(:scope, {idx, :guard}, clause.guard, acc)
            else
              {nil, acc}
            end

          {new_body, acc} = fun.(:scope, {idx, :body}, clause.body, acc)

          {%{clause | pattern: new_pattern, binds: new_binds, guard: new_guard, body: new_body},
           acc}
      end)

    new_expr = %{expr | value: new_value, clauses: clauses}
    {new_expr, acc}
  end

  def location(%Expr.Case{location: loc}) do
    loc
  end
end
