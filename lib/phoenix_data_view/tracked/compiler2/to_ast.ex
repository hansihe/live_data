defmodule Phoenix.DataView.Tracked.Compiler2.ToAst do
  alias Phoenix.DataView.Tracked.Compiler2.IR
  alias Phoenix.DataView.Tracked.Compiler2.IR.Op

  def to_ast(ir) do
    active = IR.calc_active(ir)
    uses = calc_val_uses(active, ir)

    IO.inspect ir
    IO.inspect uses

    scope = %{}

    to_block(ir.entry, uses, scope, ir)
    true = false
  end

  def calc_val_uses(active, ir) do
    Enum.reduce(active, %{}, fn block_id, uses ->
      block = IR.get_block(ir, block_id)

      values =
        IR.Op.values(block.body)
        |> Enum.filter(fn
          {:var, _} -> true
          _ -> false
        end)

      Enum.reduce(values, uses, fn value, uses ->
        Map.update(uses, value, MapSet.new([block_id]), &MapSet.put(&1, block_id))
      end)
    end)
  end

  def to_block(entry_id, uses, scope, ir) do
    entry_block = IR.get_block(ir, entry_id)
    [ret_var | _] = entry_block.args

    return_points = Map.get(uses, ret_var, MapSet.new())
    [return_id] = MapSet.to_list(return_points)

    block_seq = make_block_seq(entry_id, return_id, [], ir)

    body_exprs_ast = Enum.map_reduce(block_seq, scope, fn block_id, scope ->
      inner_block = IR.get_block(ir, block_id)
      {expr_ast, scope} = to_block_expr(inner_block, uses, scope, ir)
      {expr_ast, scope}
    end)

    {:__block__, [], body_exprs_ast}
  end

  def to_block_expr(%IR.Block{ body: %Op.Case{} } = block, uses, scope, ir) do
    IO.inspect block
    true = false
  end

  def make_block_seq(nil, _final_id, _acc, _ir) do
    throw "encountered terminal in block"
  end

  def make_block_seq(block_id, block_id, acc, _ir) do
    acc = [block_id | acc]
    Enum.reverse(acc)
  end

  def make_block_seq(curr_id, final_id, acc, ir) do
    curr_block = IR.get_block(ir, curr_id)
    next_id = Op.single_cont(curr_block)

    acc = [curr_id | acc]

    make_block_seq(next_id, final_id, acc, ir)
  end

  #def to_block_expr(block_id, uses, ir) do
  #  entry_block = IR.get_block(ir, entry_id)
  #  to_block_expr_inner(entry_block, uses, ir)
  #end

end
