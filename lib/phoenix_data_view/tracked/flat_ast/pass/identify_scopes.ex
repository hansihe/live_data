defmodule Phoenix.DataView.Tracked.FlatAst.Pass.IdentifyScopes do
  alias Phoenix.DataView.Tracked.FlatAst.Util
  alias Phoenix.DataView.Tracked.FlatAst.Expr

  defstruct []

  def identify_scopes(ast) do
    {_ast, _current_scope, _next_scope_id, scopes} =
      Util.traverse(ast, ast.root, {ast, 0, 1, %{}}, &rec_fun/3)

    scopes
  end

  def rec_fun(id, %Expr.Fn{} = expr, {ast, current_scope, next_scope_id, scopes}) do
    {next_scope_id, scopes} =
      Enum.reduce(expr.clauses, {next_scope_id, scopes}, fn {pattern, binds, guard, body},
                                                            {next_scope_id, scopes} ->
        current_scope = next_scope_id
        next_scope_id = next_scope_id + 1

        {next_scope_id, scopes} =
          if guard do
            {_ast, _current_scope, next_scope_id, scopes} =
              Util.traverse(ast, guard, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

            {next_scope_id, scopes}
          else
            {next_scope_id, scopes}
          end

        {_ast, _current_scope, next_scope_id, scopes} =
          Util.traverse(ast, body, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

        {next_scope_id, scopes}
      end)

    # {:continue, {current_scope, next_scope_id, scopes}}
    {:handled, {ast, current_scope, next_scope_id, scopes}}
  end

  def rec_fun(id, %Expr.For{} = expr, {ast, current_scope, next_scope_id, scopes}) do
    {next_scope_id, scopes} =
      if expr.into do
        {_ast, _inner_scope, next_scope_id, scopes} =
          Util.traverse(ast, expr.into, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

        {next_scope_id, scopes}
      else
        {next_scope_id, scopes}
      end

    {inner_scope_id, next_scope_id, scopes} =
      Enum.reduce(expr.items, {current_scope, next_scope_id, scopes}, fn
        {:loop, _pat, _binds, expr}, {_inner_scope, next_scope_id, scopes} ->
          {_ast, _inner_scope, next_scope_id, scopes} =
            Util.traverse(ast, expr, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

          current_scope = next_scope_id
          next_scope_id = next_scope_id + 1

          {current_scope, next_scope_id, scopes}

        {:filter, expr}, {_inner_scope, next_scope_id, scopes} ->
          {_ast, _inner_scope, next_scope_id, scopes} =
            Util.traverse(ast, expr, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

          {current_scope, next_scope_id, scopes}
      end)

    {_ast, _inner_scope, next_scope_id, scopes} =
      Util.traverse(ast, expr.inner, {ast, inner_scope_id, next_scope_id, scopes}, &rec_fun/3)

    {:handled, {ast, current_scope, next_scope_id, scopes}}
  end

  def rec_fun(id, %Expr.Case{} = expr, {ast, current_scope, next_scope_id, scopes}) do
    {_ast, _inner_scope, next_scope_id, scopes} =
      Util.traverse(ast, expr.value, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

    {next_scope_id, scopes} =
      Enum.reduce(expr.clauses, {next_scope_id, scopes}, fn {_pattern, guard, body}, {next_scope_id, scopes} ->
        current_scope = next_scope_id
        next_scope_id = next_scope_id + 1

        {_ast, _inner_scope, next_scope_id, scopes} =
          Util.traverse(ast, guard, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

        {_ast, _inner_scope, next_scope_id, scopes} =
          Util.traverse(ast, guard, {ast, current_scope, next_scope_id, scopes}, &rec_fun/3)

        {next_scope_id, scopes}
      end)

    {:handled, {ast, current_scope, next_scope_id, scopes}}
  end

  def rec_fun(id, _block, {ast, current_scope, next_scope_id, scopes}) do
    scopes = Map.put(scopes, id, {:scope, current_scope})
    {:continue, {ast, current_scope, next_scope_id, scopes}}
  end
end
