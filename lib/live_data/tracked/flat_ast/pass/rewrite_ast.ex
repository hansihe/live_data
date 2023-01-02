defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst do
  @moduledoc """
  Must be given a normalized (Expr.Scope only, no Expr.Block) FlatAST.

  Will traverse the AST from the return position, rewriting static chunks into
  templates and rewrite the AST to return those templates.

  This is done in three subpasses:
  1. MakeStructure - This is what traverses the AST from return position and
     generates the templates. No rewriting is done here, data is just collected
     for the later subpasses.
  2. ExpandDependencies - Expands the set of dependencies of the statics we
     extracted in subpass 1 into cumulative dependency sets. These cumulative
     dependency sets are what we will use later on when deciding what needs to
     be included in the rewritten function.
  3. RewriteScope - This is the subpass that actually performs the rewrite.
     The data from the other two subpasses is used here.
     The return value is the rewritten AST.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FlatAst.PDAst
  alias LiveData.Tracked.FlatAst.Pass.RewriteAst.StaticsAgent

  def rewrite(ast, full_mfa, nesting_set) do
    {:ok, out} = PDAst.init()
    new_root = PDAst.add_expr(out)
    :ok = PDAst.set_root(out, new_root)

    fn_expr = %Expr.Fn{} = FlatAst.get(ast, ast.root)

    {new_clauses, statics} =
      Enum.map_reduce(fn_expr.clauses, %{}, fn %Expr.Fn.Clause{} = clause, statics_acc ->
        new_guard =
          if clause.guard do
            raise "unimpl"
            # transcribe(guard, ast, out)
          end

        {:ok, state} = StaticsAgent.spawn()

        # First subpass of rewrite
        _rewrite_root = __MODULE__.MakeStructure.rewrite_make_structure(clause.body, ast, state)

        {:ok, %{statics: statics, traversed: traversed, dependencies: dependencies}} = StaticsAgent.finish(state)

        data = %{
          statics: statics,
          ast: ast,
          traversed: traversed,
          nesting_set: nesting_set,
          mfa: full_mfa
        }

        # Second subpass of rewrite
        expanded_dependencies = __MODULE__.ExpandDependencies.expand_dependencies(MapSet.to_list(dependencies), data, ast)
        data = Map.put(data, :dependencies, expanded_dependencies)

        # Third subpass of rewrite
        rewritten = %{}
        transcribed = %{ast.root => new_root}
        {new_body, _transcribed} = __MODULE__.RewriteScope.rewrite_scope(clause.body, data, rewritten, transcribed, out)

        clause = %{clause | guard: new_guard, body: new_body}
        {clause, Map.merge(statics_acc, statics)}
      end)

    new_expr = %{fn_expr | clauses: new_clauses}

    :ok = PDAst.set_expr(out, new_root, new_expr)
    {:ok, new_ast} = PDAst.finish(out)

    # TODO?
    new_ast = %{new_ast | patterns: ast.patterns}

    statics =
      statics
      |> Enum.map(fn
        {id, {:finished, structure, _slots, _key}} -> {id, structure}
        _ -> nil
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.into(%{})

    {:ok, new_ast, statics}
  end
end
