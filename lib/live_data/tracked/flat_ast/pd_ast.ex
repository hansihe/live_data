defmodule LiveData.Tracked.FlatAst.PDAst do
  @moduledoc """
  Utility module which stores a FlatAst in the process dictionary and
  provides a more imperative way of mutating it.

  From an external caller point of view, this looks pretty much exactly
  similar to using an Agent.
  """

  alias LiveData.Tracked.FlatAst

  def init() do
    ref = make_ref()

    Process.put(:ast, FlatAst.new())
    Process.put(:ast_tok, ref)

    {:ok, ref}
  end

  def finish(ref) do
    assert_ref(ref)

    Process.delete(:ast_tok)
    ast = Process.delete(:ast)

    {:ok, ast}
  end

  def set_root(ref, expr) do
    update(ref, fn ast ->
      ast = FlatAst.set_root(ast, expr)
      {:ok, ast}
    end)
  end

  def add_expr(ref, body \\ nil) do
    update(ref, fn ast ->
      {id, ast} = FlatAst.add_expr(ast, body)
      {id, ast}
    end)
  end

  def set_expr(ref, expr_id, body) do
    update(ref, fn ast ->
      ast = FlatAst.set_expr(ast, expr_id, body)
      {:ok, ast}
    end)
  end

  def add_bind(ref, to, selector, var) do
    update(ref, fn ast ->
      FlatAst.add_bind(ast, to, selector, var)
    end)
  end

  def add_pattern(ref, pattern) do
    update(ref, fn ast ->
      {id, ast} = FlatAst.add_pattern(ast, pattern)
      {id, ast}
    end)
  end

  def add_literal(ref, literal) do
    update(ref, fn ast ->
      {id, ast} = FlatAst.add_literal(ast, literal)
      {id, ast}
    end)
  end

  defp update(ref, fun) do
    assert_ref(ref)

    {ret, ir} = fun.(Process.get(:ast))
    Process.put(:ast, ir)

    ret
  end

  defp assert_ref(ref) do
    pd_ref = Process.get(:ast_tok)

    if ref != pd_ref do
      raise "invalid ref (#{ref} != #{pd_ref})"
    end
  end
end
