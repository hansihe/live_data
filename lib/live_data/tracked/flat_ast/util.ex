defmodule LiveData.Tracked.FlatAst.Util do
  @moduledoc false

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr

  def unique_integer do
    :erlang.unique_integer()
  end

  @doc """
  Given an arbitrarily nested list data structure, will flatten it into a single
  list.
  """
  def recursive_flatten(val) do
    res = recursive_flatten_rec(val, [])
    Enum.reverse(res)
  end

  defp recursive_flatten_rec([], acc) do
    acc
  end

  defp recursive_flatten_rec([head | tail], acc) do
    acc = recursive_flatten_rec(head, acc)
    recursive_flatten_rec(tail, acc)
  end

  defp recursive_flatten_rec(value, acc) do
    [value | acc]
  end

  @doc """
  Traverses the AST starting at `id`.

  User provided function will be called on a node before its children.
  """
  def traverse(ast, id, expr \\ nil, acc, fun)

  def traverse(ast, id, nil, acc, fun) do
    expr = FlatAst.get(ast, id)
    traverse(ast, id, expr, acc, fun)
  end

  def traverse(ast, id, expr, acc, fun) do
    case fun.(id, expr, acc) do
      {:handled, acc} ->
        acc

      {:continue, acc} ->
        children = child_exprs(expr)
        Enum.reduce(children, acc, fn child, acc -> traverse(ast, child, acc, fun) end)
    end
  end

  @doc """
  Traverses the AST starting at `id`.

  User provided function will be called on a node after its children.
  """
  def traverse_post(ast, id, expr \\ nil, acc, fun)

  def traverse_post(ast, id, nil, acc, fun) do
    expr = FlatAst.get(ast, id)
    traverse(ast, id, expr, acc, fun)
  end

  def traverse_post(ast, id, expr, acc, fun) do
    children = child_exprs(expr)
    Enum.reduce(children, acc, fn child, acc -> traverse_post(ast, child, acc, fun) end)

    fun.(id, expr, acc)
  end

  @doc """
  Expression traversal/update primitive.

  Given an expression, an accululator and a function, will apply the function
  over all subexpressions of the expression.

  The accumulator will be woven through, and will be returned alongside the
  updated expression.
  """
  def transform_expr(expr, acc, fun)

  def transform_expr(%{__struct__: _} = expr, acc, fun) do
    Expr.transform(expr, acc, fun)
  end

  def transform_expr({:bind, _bid} = bind, acc, fun) do
    fun.(:bind, nil, bind, acc)
  end

  def transform_expr({:literal_value, _lid} = literal_id, acc, fun) do
    fun.(:literal, nil, literal_id, acc)
  end

  def reduce_expr(expr, acc, fun) do
    {_new_expr, acc} =
      transform_expr(expr, acc, fn
        kind, selector, value, acc ->
          acc = fun.(kind, selector, value, acc)
          {value, acc}
      end)

    acc
  end

  @doc """
  Given an expression, will return a list of all subexpressions.
  """
  def child_exprs(expr) do
    reduce_expr(expr, [], fn
      :value, _selector, child_expr_id, acc ->
        [child_expr_id | acc]
      :scope, _selector, child_expr_id, acc ->
        [child_expr_id | acc]
      _, _, _, acc ->
        acc
    end)
    |> Enum.reverse()
  end
end
