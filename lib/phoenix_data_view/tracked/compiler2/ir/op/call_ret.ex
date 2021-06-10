alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.CallRet do
  defstruct cont: nil, value: nil

  def new(cont, value) do
    %__MODULE__{
      cont: cont,
      value: value
    }
  end
end

defimpl Op, for: Op.CallRet do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    [op.cont, op.value]
  end

  def single_cont(_op) do
    nil
  end
end
