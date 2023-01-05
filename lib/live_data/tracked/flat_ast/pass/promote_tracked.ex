defmodule LiveData.Tracked.FlatAst.Pass.PromoteTracked do
  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr

  defp get_literal_or_nil(ast, value) do
    case FlatAst.get_literal_id_by_value(ast, value) do
      {:ok, literal} -> literal
      :error -> nil
    end
  end

  def promote_tracked(ast) do
    # TODO do full tree traverse using a common util?

    dummy_lit = get_literal_or_nil(ast, LiveData.Tracked.Dummy)
    track_lit = get_literal_or_nil(ast, :track_stub)

    exprs = ast.exprs
    |> Enum.map(fn
      {expr_id, %Expr.CallMF{module: ^dummy_lit, function: ^track_lit, args: [inner_id]}} when dummy_lit != nil ->
        # TODO report errors
        call_expr = %Expr.CallMF{} = FlatAst.get(ast, inner_id)
        case call_expr.module do
          {:literal, _} -> nil
          nil -> nil
        end
        {:literal, _} = call_expr.function

        new_expr = Expr.CallTracked.new(call_expr)

        {expr_id, new_expr}

      {expr_id, expr} ->
        {expr_id, expr}
    end)
    |> Enum.into(%{})

    ast = %{ast | exprs: exprs}
    {:ok, ast}
  end

end
