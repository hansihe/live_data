defmodule Phoenix.LiveData.Tracked.FlatAst.Expr.Case do
  defstruct value: nil, clauses: []

  def new({:expr, _eid} = expr) do
    %__MODULE__{
      value: expr
    }
  end

  def add_clause(cas, {:pattern, _peid} = pattern, {:expr, _geid} = guard, {:expr, _beid} = body) do
    %{cas | clauses: [{pattern, guard, body} | cas.clauses]}
  end
end
