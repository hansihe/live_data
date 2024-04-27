defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst.RewriteScope do
  @moduledoc """
  Third subpass of rewriting.

  This will take the data collected in the two first passes, and perform the
  actual rewriting.
  """

  # alias LiveData.Tracked.TraceCollector
  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FlatAst.PDAst
  alias LiveData.Tracked.FlatAst.Util
  alias LiveData.Tracked.FragmentTree.Slot

  def rewrite_scope(expr_id, data, rewritten, transcribed, out) do
    %Expr.Scope{exprs: scope_exprs} = FlatAst.get(data.ast, expr_id)
    old_rewritten = rewritten
    # if LiveData.debug_prints?() do
    #  IO.inspect scope_exprs
    #  IO.inspect Enum.filter(scope_exprs, &MapSet.member?(data.dependencies, &1))
    #  IO.inspect Enum.filter(scope_exprs, &MapSet.member?(data.traversed, &1))
    # end

    # Step 1: Transcribe dependencies
    {transcribed_exprs, transcribed} =
      scope_exprs
      |> Enum.filter(&MapSet.member?(data.dependencies, &1))
      |> Enum.map_reduce(transcribed, fn dep, map ->
        {expr, map} = Util.Transcribe.transcribe(dep, data, map, &Map.fetch!(rewritten, &1), out)
        {expr, map}
      end)

    # Step 2: Rewrite statics
    {rewritten_exprs, rewritten} =
      scope_exprs
      |> Enum.filter(&MapSet.member?(data.traversed, &1))
      |> Enum.map_reduce(rewritten, &rewrite_scope_expr(&1, data, &2, transcribed, out))

    {rewritten_result, _rewritten} =
      rewrite_scope_expr(expr_id, data, rewritten, transcribed, out)

    scope_exprs = Util.recursive_flatten([transcribed_exprs, rewritten_exprs, rewritten_result])

    new_expr_id = PDAst.add_expr(out, Expr.Scope.new(scope_exprs))

    {new_expr_id, old_rewritten}
  end

  def rewrite_scope_expr(expr_id, data, rewritten, transcribed, out) do
    case Map.fetch(data.statics, expr_id) do
      :error ->
        expr = FlatAst.get(data.ast, expr_id)
        rewrite_scope_expr(expr, expr_id, data, rewritten, transcribed, out)

      {:ok, %{state: :unfinished, slots: [_ret_expr_id]}} ->
        {[], rewritten}

      # Special case, the whole static is useless.
      {:ok,
       %{state: :finished, static_structure: %Slot{num: 0}, slots: [_inner_expr_id], key: nil}} ->
        raise "unimpl"

      # rewritten = Map.put(rewritten, expr_id, inner_expr_id)
      # {inner_expr_id, rewritten}

      {:ok, %{state: :finished, static_structure: static, slots: slots, key: key}} ->
        new_slots =
          Enum.map(slots, fn
            {:bind, _bid} = bind ->
              data = FlatAst.get_bind_data(data.ast, bind)
              new_expr = Map.get(rewritten, data.expr) || Map.fetch!(transcribed, data.expr)
              PDAst.add_bind(out, new_expr, data.selector, data.variable)

            {:expr, _eid} = expr_id ->
              Map.get(rewritten, expr_id) || Map.fetch!(transcribed, expr_id)
          end)

        new_key =
          if key do
            Map.fetch!(transcribed, key)
          end

        new_expr = Expr.MakeStatic.new(expr_id, static, new_slots, data.mfa, new_key)
        new_expr_id = PDAst.add_expr(out, new_expr)
        rewritten = Map.put(rewritten, expr_id, new_expr_id)
        {new_expr_id, rewritten}
    end
  end

  def rewrite_scope_expr(expr, expr_id, data, rewritten, transcribed, out) do
    new_expr_id = PDAst.add_expr(out)
    rewritten = Map.put(rewritten, expr_id, new_expr_id)

    {new_expr, rewritten} =
      Util.transform_expr(expr, rewritten, fn kind, selector, inner, rewritten ->
        case {expr, kind, selector} do
          {%Expr.For{}, :scope, :inner} ->
            {new_inner, _rewritten} = rewrite_scope(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {%Expr.Case{}, :scope, {_idx, :body}} ->
            {new_inner, _rewritten} = rewrite_scope(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {_, :scope, _} ->
            {new_inner, _transcribed} =
              Util.Transcribe.transcribe(
                inner,
                data,
                transcribed,
                &Map.fetch!(rewritten, &1),
                out
              )

            {new_inner, rewritten}

          {_, :value, _} ->
            new_inner = rewrite_resolve(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {_, :bind, _} ->
            new_inner = rewrite_resolve(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {_, :bind_ref, _} ->
            new_inner = rewrite_resolve(inner, data, rewritten, transcribed, out)
            {new_inner, rewritten}

          {_, :pattern, _} ->
            {inner, rewritten}
        end
      end)

    :ok = PDAst.set_expr(out, new_expr_id, new_expr)
    rewritten = Map.put(rewritten, expr_id, new_expr_id)

    {new_expr_id, rewritten}
  end

  def rewrite_resolve({:bind, _bid} = bind, data, rewritten, transcribed, out) do
    data = FlatAst.get_bind_data(data.ast, bind)

    new_expr =
      {:expr, _new_eid} = Map.get(rewritten, data.expr) || Map.fetch!(transcribed, data.expr)

    PDAst.add_bind(out, new_expr, data.selector, data.variable)
  end

  def rewrite_resolve({:expr, _eid} = expr_id, _data, rewritten, transcribed, _out) do
    Map.get(rewritten, expr_id) || Map.fetch!(transcribed, expr_id)
  end

  def rewrite_resolve({:literal, _lit_id} = literal_id, data, _rewritten, _transcribed, out) do
    {:literal_value, literal} = FlatAst.get(data.ast, literal_id)
    PDAst.add_literal(out, literal)
  end
end
