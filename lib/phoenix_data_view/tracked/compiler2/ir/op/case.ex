alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.Case do
  defstruct cont: nil, clauses: []

  def new(cont) do
    %__MODULE__{
      cont: cont
    }
  end

  def add_clause(cas = %__MODULE__{}, pattern, binds, clause_block) do
    %{
      cas
      | clauses: [{pattern, binds, clause_block} | cas.clauses]
    }
  end
end

defimpl Op, for: Op.Case do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont | Enum.map(op.clauses, fn {_pat, _binds, clause_block} -> clause_block end)]
  end

  def single_cont(op) do
    op.cont
  end
end
