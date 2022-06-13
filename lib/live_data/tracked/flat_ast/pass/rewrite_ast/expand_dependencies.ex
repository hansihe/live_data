defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst.ExpandDependencies do
  @moduledoc """
  Second subpass of rewriting.

  Given a set of initial nodes, will collect a set of all cumulative
  dependencies these involves.

  This has the effect of doing dead code elimination, and duplicating any
  expressions that are used in both the return value position and regular value
  positions.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FlatAst.Util

  def expand_dependencies(to_visit, data, ast) do
    to_visit_tuples = Enum.map(to_visit, &{false, &1})
    original = MapSet.new(to_visit)
    expand_dependencies_inner(to_visit_tuples, original, MapSet.new(), data, ast)
  end

  def expand_dependencies_inner([{_, nil} | tail], original, visited, data, ast) do
    expand_dependencies_inner(tail, original, visited, data, ast)
  end

  def expand_dependencies_inner([{from_child, expr_id} | tail], original, visited, data, ast) do
    if MapSet.member?(visited, expr_id) do
      expand_dependencies_inner(tail, original, visited, data, ast)
    else
      expr = FlatAst.get(ast, expr_id)

      case {from_child, expr} do
        {_, %Expr.Var{ref_expr: ref_expr}} ->
          visited = MapSet.put(visited, expr_id)
          item = process_expr_id(ref_expr, expr_id, data)
          expand_dependencies_inner([item | tail], original, visited, data, ast)

        {true, %Expr.Scope{}} ->
          raise "unreachable"

        {false, %Expr.Scope{exprs: exprs}} ->
          last =
            List.last(exprs)
            |> process_expr_id(expr_id, data)

          expand_dependencies_inner([last | tail], original, visited, data, ast)

        {true, _expr} ->
          children =
            expr
            |> child_exprs_without_traversed()
            |> Enum.map(&process_expr_id(&1, expr_id, data))

          expand_dependencies_inner(children ++ tail, original, visited, data, ast)

        {false, _expr} ->
          visited = MapSet.put(visited, expr_id)

          children =
            Util.child_exprs(expr)
            |> Enum.map(&process_expr_id(&1, expr_id, data))

          expand_dependencies_inner(children ++ tail, original, visited, data, ast)
      end
    end
  end

  def expand_dependencies_inner([], _original, visited, _data, _ast) do
    visited
  end

  def child_exprs_without_traversed(%Expr.Case{} = expr) do
    [expr.value]
  end

  def child_exprs_without_traversed(%Expr.For{} = expr) do
    %{expr | inner: nil}
    |> Util.child_exprs()
    |> Enum.filter(&(&1 != nil))
  end

  def child_exprs_without_traversed(%Expr.Fn{}) do
    []
  end

  def process_expr_id({:expr_bind, eid, _selector}, {:expr, _eid} = parent, data) do
    ref_expr_id = {:expr, eid}

    if MapSet.member?(data.nesting_set, {ref_expr_id, parent}) do
      {true, ref_expr_id}
    else
      {false, ref_expr_id}
    end
  end

  def process_expr_id({:expr, _eid} = expr_id, _parent, _data) do
    {false, expr_id}
  end

  def process_expr_id({:literal, _lit_id} = expr_id, _parent, _data) do
    {false, expr_id}
  end
end
