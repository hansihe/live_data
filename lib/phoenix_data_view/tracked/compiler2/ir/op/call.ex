alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.Call do
  defstruct fun: nil, cont: nil, args: []

  def new(fun, cont, args) do
    %__MODULE__{
      fun: fun,
      cont: cont,
      args: args
    }
  end
end

defimpl Op, for: Op.Call do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont, op.fun | op.args]
  end

  def single_cont(op) do
    op.cont
  end
end
