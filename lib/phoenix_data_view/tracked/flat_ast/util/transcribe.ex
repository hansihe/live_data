defmodule Phoenix.DataView.Tracked.FlatAst.Util.Transcribe do
  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.FlatAst.Expr
  alias Phoenix.DataView.Tracked.FlatAst.PDAst
  alias Phoenix.DataView.Tracked.FlatAst.Util

  @doc """
  Directly transcribes the given selection from the input AST to the output.

  When a value is not found in the regular `map`, `backup_resolve/1` is called.
  This is useful in the case where we have a separate, semantically different
  map of parent transcribed expressions.
  """
  def transcribe(expr_id, data, map, backup_resolve, out) do
    false = Map.has_key?(map, expr_id)
    expr = FlatAst.get(data.ast, expr_id)

    {new_expr_id, map} = transcribe(expr, expr_id, data, map, backup_resolve, out)
    map = Map.put(map, expr_id, new_expr_id)

    {new_expr_id, map}
  end

  def transcribe(%Expr.Scope{exprs: exprs}, _expr_id, data, map, backup_resolve, out) do
    {new_exprs, _map} =
      Enum.map_reduce(exprs, map, fn expr, map ->
        transcribe(expr, data, map, backup_resolve, out)
      end)

    new_expr = %Expr.Scope{exprs: new_exprs}
    new_expr_id = PDAst.add_expr(out, new_expr)

    {new_expr_id, map}
  end

  def transcribe(expr, expr_id, data, map, backup_resolve, out) do
    new_expr_id = PDAst.add_expr(out)
    map = Map.put(map, expr_id, new_expr_id)

    {new_expr, map} =
      Util.transform_expr(expr, map, fn
        :value, _selector, inner_expr_id, map ->
          new_expr_id = transcribe_maybe_scope(inner_expr_id, data, map, backup_resolve, out)
          {new_expr_id, map}

        :pattern, _selector, {pattern, binds}, map ->
          {{pattern, binds}, map}
      end)

    :ok = PDAst.set_expr(out, new_expr_id, new_expr)

    {new_expr_id, map}
  end

  def transcribe_maybe_scope(expr_id, data, map, backup_resolve, out) do
    case FlatAst.get(data.ast, expr_id) do
      %Expr.Scope{} ->
        {new_expr_id, _map} = transcribe(expr_id, data, map, backup_resolve, out)
        new_expr_id

      {:expr_bind, _eid, _selector} = bind ->
        transcribe_bind(bind, map, backup_resolve)

      {:literal, lit} ->
        PDAst.add_literal(out, lit)

      _ ->
        Map.fetch!(map, expr_id)
    end
  end

  def transcribe_bind({:expr_bind, eid, selector}, map, backup_resolve) do
    expr_id = {:expr, eid}
    {:expr, new_eid} = Map.get(map, expr_id) || backup_resolve.(expr_id)
    {:expr_bind, new_eid, selector}
  end
end
