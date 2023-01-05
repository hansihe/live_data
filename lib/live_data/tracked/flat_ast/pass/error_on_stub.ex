defmodule LiveData.Tracked.FlatAst.Pass.ErrorOnStub do
  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FlatAst.Util

  defp get_literal_or_nil(ast, value) do
    case FlatAst.get_literal_id_by_value(ast, value) do
      {:ok, literal} -> literal
      :error -> nil
    end
  end

  def error_on_stub(ast, file) do
    dummy_module_lit = get_literal_or_nil(ast, LiveData.Tracked.Dummy)
    keyed_lit = get_literal_or_nil(ast, :keyed_stub)
    tracked_lit = get_literal_or_nil(ast, :tracked_stub)

    Util.traverse(ast, ast.root, nil, fn
      #_id, %Expr.CallTracked{}

      _id, %Expr.CallMF{module: ^dummy_module_lit} = expr, nil when dummy_module_lit != nil ->
        {line, _col} = expr.location

        message = case expr.function do
          ^keyed_lit ->
            "deft error: `keyed` used in non-return position"

          ^tracked_lit ->
            raise "unreachable"
            #"deft error: `tracked` used in non-return position"
        end

        raise %CompileError{
          file: file,
          line: line,
          description: message
        }

        {:handled, nil}

      _id, _expr, nil ->
        {:continue, nil}
    end)

    :ok
  end

end
