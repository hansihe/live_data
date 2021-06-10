alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.CaptureFun do
  defstruct cont: nil, module: nil, function: nil, arity: nil

  def new(cont, module, function, arity) do
    %__MODULE__{
      cont: cont,
      module: module,
      function: function,
      arity: arity
    }
  end
end

defimpl Op, for: Op.CaptureFun do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont, op.module, op.function, op.arity]
  end

  def single_cont(op) do
    op.cont
  end
end
