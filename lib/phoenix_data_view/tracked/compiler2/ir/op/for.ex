alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.For do
  defstruct into: nil, inner: nil, cont: nil

  def new(cont, inner, into) do
    %__MODULE__{
      cont: cont,
      inner: inner,
      into: into
    }
  end
end

defimpl Op, for: Op.For do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont, op.inner, op.into]
  end

  def single_cont(op) do
    op.cont
  end
end
