defmodule Phoenix.DataView.Tracked.Compiler2.PDIR do
  alias Phoenix.DataView.Tracked.Compiler2.IR

  def init() do
    ref = make_ref()

    Process.put(:ir, IR.new())
    Process.put(:ir_tok, ref)

    {:ok, ref}
  end

  def finish(ref) do
    assert_ref(ref)

    Process.delete(:ir_tok)
    ir = Process.delete(:ir)

    {:ok, ir}
  end

  def set_entry(ref, block) do
    update(ref, fn ir ->
      ir = IR.set_entry(ir, block)
      {:ok, ir}
    end)
  end

  def add_block(ref, num_args) do
    update(ref, fn ir ->
      {block, args, ir} = IR.add_block(ir, num_args)
      {{block, args}, ir}
    end)
  end

  def set_body(ref, block, body) do
    update(ref, fn ir ->
      ir = IR.set_body(ir, block, body)
      {:ok, ir}
    end)
  end

  def add_literal(ref, literal) do
    update(ref, fn ir ->
      {var, ir} = IR.add_literal(ir, literal)
      {var, ir}
    end)
  end

  defp update(ref, fun) do
    assert_ref(ref)

    {ret, ir} = fun.(Process.get(:ir))
    Process.put(:ir, ir)

    ret
  end

  defp assert_ref(ref) do
    pd_ref = Process.get(:ir_tok)
    if ref != pd_ref do
      IO.inspect {:invalid_ref, ref, pd_ref}
      true = false
    end
  end

end
