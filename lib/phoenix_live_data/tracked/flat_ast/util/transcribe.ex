defmodule Phoenix.LiveData.Tracked.FlatAst.Util.Transcribe do
  alias Phoenix.LiveData.Tracked.FlatAst
  alias Phoenix.LiveData.Tracked.FlatAst.Expr
  alias Phoenix.LiveData.Tracked.FlatAst.PDAst
  alias Phoenix.LiveData.Tracked.FlatAst.Util

  @doc """
  Directly transcribes the given selection from the input AST to the output.

  When a value is not found in the regular `map`, `backup_resolve/1` is called.
  This is useful in the case where we have a separate, semantically different
  map of parent transcribed expressions.
  """
  def transcribe({:literal, _} = lit_id, data, map, backup_resolve, out) do
    {:literal, lit} = FlatAst.get(data.ast, lit_id)
    new_lit_id = PDAst.add_literal(out, lit)
    {new_lit_id, map}
  end

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

  #def transcribe(%Expr.Case{} = case_expr, _expr_id, data, map, backup_resolve, out) do
  #  true = false
  #end

  def transcribe(expr, expr_id, data, map, backup_resolve, out) do
    new_expr_id = PDAst.add_expr(out)
    map = Map.put(map, expr_id, new_expr_id)

    {new_expr, map} =
      Util.transform_expr(expr, map, fn
        :value, _selector, inner_expr_id, map ->
          new_expr_id = transcribe_maybe_scope(inner_expr_id, data, map, backup_resolve, out)
          {new_expr_id, map}

        :scope, _selector, inner_expr_id, map ->
          new_expr_id = transcribe_maybe_scope(inner_expr_id, data, map, backup_resolve, out)
          {new_expr_id, map}

        :pattern, _selector, {pattern, binds}, map ->
          {{pattern, binds}, map}

        :literal, _selector, literal, map ->
          {:literal, lit} = FlatAst.get(data.ast, literal)
          new_lit_id = PDAst.add_literal(out, lit)
          {new_lit_id, map}

        :ref, _selector, {:expr_bind, eid, bind_selector}, map ->
          {:expr, new_eid} = Map.get(map, {:expr, eid}) || backup_resolve.({:expr, eid})
          new_ref = {:expr_bind, new_eid, bind_selector}

          {new_ref, map}

        :ref, _selector, ref_expr, map ->
          {Map.fetch!(map, ref_expr), map}
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
