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

    string_chars_lit = get_literal_or_nil(ast, String.Chars)
    to_string_lit = get_literal_or_nil(ast, :to_string)

    dummy_lit = get_literal_or_nil(ast, LiveData.Tracked.Dummy)
    track_lit = get_literal_or_nil(ast, :track_stub)
    lifecycle_hook_lit = get_literal_or_nil(ast, :lifecycle_hook_stub)

    exprs =
      ast.exprs
      |> Enum.map(fn
        {expr_id, %Expr.CallMF{module: ^dummy_lit, function: ^track_lit, args: [inner_id]}}
        when dummy_lit != nil ->
          # TODO report errors
          call_expr = %Expr.CallMF{} = FlatAst.get(ast, inner_id)

          case call_expr.module do
            {:literal, _} -> nil
            nil -> nil
          end

          {:literal, _} = call_expr.function

          new_expr = Expr.CallTracked.new(call_expr)

          {expr_id, new_expr}

        {expr_id,
         %Expr.CallMF{module: ^dummy_lit, function: ^lifecycle_hook_lit, args: [module, args, subtrees]}}
        when dummy_lit != nil ->
          # TODO report errors
          # TODO validate subtrees argument

          {:literal_value, module_lit} = FlatAst.get(ast, module)
          true = is_atom(module_lit)

          args_list = collect_static_list(args, ast)
          subtrees_list = collect_static_list(subtrees, ast)

          new_expr = Expr.LifecycleHook.new(module_lit, args_list, subtrees_list)

          {expr_id, new_expr}

        {expr_id,
         %Expr.CallMF{module: ^string_chars_lit, function: ^to_string_lit, args: [value]}}
        when string_chars_lit != nil and to_string_lit != nil ->
          new_expr = Expr.Intrinsic.new(:to_string, [value])
          {expr_id, new_expr}

        {expr_id, expr} ->
          {expr_id, expr}
      end)
      |> Enum.into(%{})

    ast = %{ast | exprs: exprs}
    {:ok, ast}
  end

  def collect_static_list(expr, ast, acc \\ []) do
    case FlatAst.get(ast, expr) do
      %LiveData.Tracked.FlatAst.Expr.MakeCons{head: head, tail: tail} ->
        collect_static_list(tail, ast, [head | acc])

      {:literal_value, []} ->
        Enum.reverse(acc)

        # TODO handle other
    end
  end
end
