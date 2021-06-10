alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.ForLoop do
  defstruct pattern: nil, inner: nil, cont: nil, acc: nil, binds: nil

  def new(cont, inner, acc, pattern, binds) do
    %__MODULE__{
      cont: cont,
      inner: inner,
      acc: acc,
      pattern: pattern,
      binds: binds
    }
  end
end

defimpl Op, for: Op.ForLoop do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont, op.inner, op.acc]
  end

  def single_cont(op) do
    op.cont
  end
end
