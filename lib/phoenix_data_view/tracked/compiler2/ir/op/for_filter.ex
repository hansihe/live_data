alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.ForFilter do
  defstruct value: nil, inner: nil, cont: nil

  def new(cont, inner, value) do
    %__MODULE__{
      cont: cont,
      inner: inner,
      value: value
    }
  end
end

defimpl Op, for: Op.ForFilter do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont, op.inner, op.value]
  end

  def single_cont(op) do
    op.cont
  end
end
