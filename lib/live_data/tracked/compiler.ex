defmodule LiveData.Tracked.Compiler do
  @moduledoc false

  # Top-level entry point for the deft compiler.

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.Util
  alias LiveData.Tracked.TraceCollector

  def compile(module, file, {name, arity} = fun, kind, meta, clauses) do
    full_mfa = {module, name, arity}

    try do
      TraceCollector.with_trace(full_mfa, fn _trace_key ->
        compile_inner(module, file, fun, kind, meta, clauses)
      end)
    rescue
      e in CompileError ->
        # We strip the full stacktrace because it is not relevant to a reported
        # compiler error, it would not add any relevant context and would only
        # contribute visual noise.
        reraise e, []
      e ->
        if not TraceCollector.in_test?() do
          IO.puts("================ INTERNAL DEFT COMPILER ERROR ================")
          IO.puts("Internal error in LiveData deft compiler while compiling `#{module}.#{name}/#{arity}` in `#{file}`.")
          IO.puts("This is a bug in LiveData. Please submit an issue at https://github.com/hansihe/live_data.")
          IO.puts("Make sure to include the source code of the function named above in the issue.")
          IO.puts("==============================================================")
        end
        reraise e, __STACKTRACE__
    end
  end

  defp compile_inner(module, file, {name, arity} = fun, kind, _meta, clauses) do
    full_mfa = {module, name, arity}

    meta_fun_name = String.to_atom("__tracked_meta__#{name}__#{arity}__")
    tracked_fun_name = String.to_atom("__tracked__#{name}__")

    #if LiveData.debug_prints?(), do: IO.inspect(clauses, label: :elixir_ast_clauses, limit: :infinity)
    TraceCollector.log(:elixir_ast_clauses, clauses)

    {:ok, ast} = FlatAst.FromAst.from_clauses(clauses)
    TraceCollector.log(:base_flat_ast, ast)
    {:ok, ast} = FlatAst.Pass.PromoteTracked.promote_tracked(ast)
    ast = FlatAst.Pass.Normalize.normalize(ast)
    #if LiveData.debug_prints?(), do: IO.inspect(ast, label: :normalized_flat_ast, limit: :infinity)
    TraceCollector.log(:normalized_flat_ast, ast)

    nesting = FlatAst.Pass.CalculateNesting.calculate_nesting(ast)

    # TODO we might not want to do it this way
    # This generates m*n entries where m is the number of expressions and n
    # is the nesting level.
    nesting_set =
      nesting
      |> Enum.map(fn {expr, path} ->
        Enum.map(path, &{&1, expr})
      end)
      |> Enum.concat()
      |> Enum.into(MapSet.new())

    {:ok, new_ast, statics} = FlatAst.Pass.RewriteAst.rewrite(
      ast, full_mfa, nesting_set)

    TraceCollector.log(:final_flat_ast, new_ast)

    :ok = FlatAst.Pass.ErrorOnStub.error_on_stub(new_ast, file)

    expr = FlatAst.ToAst.to_expr(new_ast, pretty: true)
    tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)
    #if LiveData.debug_prints?(), do: IO.puts(Macro.to_string(tracked_defs))
    TraceCollector.log(:tracked_defs, Macro.to_string(tracked_defs))

    meta_fun_ast =
      quote do
        def unquote(meta_fun_name)(:statics), do: unquote(Macro.escape(statics))
      end

    #if LiveData.debug_prints?(), do: IO.puts(Macro.to_string(meta_fun_ast))
    TraceCollector.log(:meta_defs, Macro.to_string(meta_fun_ast))

    [
      make_normal_fun(kind, fun, clauses),
      tracked_defs,
      meta_fun_ast,
    ]
  end

  # Passthrough function

  def make_normal_fun(kind, {name, _arity}, clauses) do
    clauses
    |> Enum.map(fn {opts, args, [], body} ->
      inner = [
        {name, opts, args},
        [
          do: body
        ]
      ]
      {kind, opts, inner}
    end)
  end

end
