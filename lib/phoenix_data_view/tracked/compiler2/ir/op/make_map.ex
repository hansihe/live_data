alias Phoenix.DataView.Tracked.Compiler2.IR.Op

defmodule Op.MakeMap do
  defstruct cont: nil, map: nil, kvs: nil

  def new(cont, map, kvs) do
    %__MODULE__{
      cont: cont,
      map: map,
      kvs: kvs
    }
  end
end

defimpl Op, for: Op.MakeMap do
  def outgoing(op) do
    [op.cont]
  end

  def values(op) do
    kvs = Enum.flat_map(op.kvs, fn {k, v} -> [k, v] end)

    if op.map do
      [op.cont, op.map | kvs]
    else
      [op.cont | kvs]
    end
  end

  def single_cont(op) do
    op.cont
  end
end
