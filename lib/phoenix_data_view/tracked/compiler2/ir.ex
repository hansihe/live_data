defmodule Phoenix.DataView.Tracked.Compiler2.IR do
  alias Phoenix.DataView.Tracked.Compiler2.IR.Block
  alias Phoenix.DataView.Tracked.Compiler2.IR.Op

  defstruct entry: nil, literals: %{}, literals_back: %{}, blocks: %{}, next_block: 0, next_var: 0

  def new() do
    %__MODULE__{}
  end

  def get_block(ir, {:block, _bid} = block_id) do
    Map.fetch!(ir.blocks, block_id)
  end

  def calc_active(ir) do
    calc_active_rec([ir.entry], MapSet.new(), ir)
  end

  defp calc_active_rec([], visited, _ir) do
    visited
  end

  defp calc_active_rec([block_id | rest], visited, ir) do
    if MapSet.member?(visited, block_id) do
      calc_active_rec(rest, visited, ir)
    else
      visited = MapSet.put(visited, block_id)

      block = get_block(ir, block_id)

      blocks =
        Op.values(block.body)
        |> Enum.filter(fn
          {:block, _bid} -> true
          _ -> false
        end)

      calc_active_rec(blocks ++ rest, visited, ir)
    end
  end

  def set_entry(ir, block_id) do
    %{ir | entry: block_id}
  end

  def set_body(ir, block_id, body) do
    update_in(ir.blocks[block_id], fn block ->
      nil = block.body
      %{
        block
        | body: body
      }
    end)
  end

  def add_literal(ir, literal) do
    case Map.fetch(ir.literals_back, literal) do
      {:ok, var} -> {var, ir}
      _ ->
        {var_id, ir} = next_var_id(ir)
        ir = %{
          ir |
          literals: Map.put(ir.literals, var_id, literal),
          literals_back: Map.put(ir.literals_back, literal, var_id)
        }
        {var_id, ir}
    end

  end

  def add_block(ir, num_args \\ 0) do
    {block_id, ir} = next_block_id(ir)

    {args, ir} =
      iter(num_args)
      |> Enum.map_reduce(ir, fn _idx, ir ->
        next_var_id(ir)
      end)

    block = %Block{
      id: block_id,
      args: args
    }

    ir = %{
      ir
      | blocks: Map.put(ir.blocks, block_id, block)
    }

    {block_id, args, ir}
  end

  def next_block_id(ir) do
    block_id = ir.next_block

    ir = %{
      ir
      | next_block: block_id + 1
    }

    {{:block, block_id}, ir}
  end

  def next_var_id(ir) do
    var_id = ir.next_var

    ir = %{
      ir
      | next_var: var_id + 1
    }

    {{:var, var_id}, ir}
  end

  def iter(count) do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(count)
  end
end
