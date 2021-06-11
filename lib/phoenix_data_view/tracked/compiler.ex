defmodule Phoenix.DataView.Tracked.Compiler do
  alias Phoenix.DataView.Tracked.Compiler
  alias Phoenix.DataView.Tracked.Compiler2
  alias Phoenix.DataView.Tracked.Dummy
  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.Util

  def compile(module, {name, arity} = fun, kind, meta, clauses) do
    meta_fun_name = String.to_atom("__tracked_meta__#{name}__#{arity}__")
    tracked_fun_name = String.to_atom("__tracked__#{name}__")

    {:ok, ast} = FlatAst.FromAst.from_clauses(clauses)
    ast = FlatAst.Pass.Normalize.normalize(ast)

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

    {:ok, new_ast, statics} = FlatAst.Pass.RewriteAst.rewrite(ast, nesting_set)

    expr = FlatAst.ToAst.to_expr(new_ast)
    tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)

    meta_fun_ast =
      quote do
        def unquote(meta_fun_name)(:statics), do: unquote(Macro.escape(statics))
      end

    [
      make_normal_fun(kind, fun, clauses),
      tracked_defs,
      meta_fun_ast,
    ]
  end

  # Passthrough function

  def make_normal_fun(kind, {name, arity}, clauses) do
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

  # IDs function

  def make_ids_fun(module, kind, name, {orig_name, orig_arity}, ids_state) do
    ids_expr =
      ids_state.fragment_lines
      |> Enum.with_index()
      |> Enum.reduce(
        quote do
          ids
        end,
        fn {{id, line}, idx}, acc ->
          quote do
            Map.put(unquote(acc), {scope_id, unquote(id)}, %{
              num: counter + unquote(idx),
              line: unquote(line)
            })
          end
        end
      )

    tracked_calls_expr =
      ids_state.tracked_calls
      |> Enum.reverse()
      |> Enum.reduce(
        quote do
          state
        end,
        fn {module, name, arity}, acc ->
          ids_fun_name = String.to_atom("__tracked_ids_#{name}_#{arity}__")

          quote do
            unquote(ids_fun_name)(unquote(acc))
          end
        end
      )

    num_ids = ids_state.counter

    quote do
      unquote(kind)(unquote(name)(state)) do
        scope_id = {unquote(module), unquote(orig_name), unquote(orig_arity)}

        if Map.has_key?(state.visited, scope_id) do
          state
        else
          %{ids: ids, visited: visited, counter: counter} = state
          visited = Map.put(visited, scope_id, nil)

          ids = unquote(ids_expr)

          state = %{
            state
            | ids: ids,
              visited: visited,
              counter: counter + unquote(num_ids)
          }

          state = unquote(tracked_calls_expr)

          state
        end
      end
    end
  end

  # Terminal macros

  defmacro track_stub(call) do
    {mfa, args} = Macro.decompose_call(call)
    new_mfa = mfa_to_tracked(mfa)
    {new_mfa, [line: __CALLER__.line], args}
  end

  defp mfa_to_tracked(name) when is_atom(name) do
    string = Atom.to_string(name)
    new = "__tracked_#{string}__"
    String.to_atom(new)
  end

  defp mfa_to_tracked({name, arity}) do
    {mfa_to_tracked(name), arity}
  end

  defmacro keyed_stub(key, do: body) do
    do_keyed(key, body, __CALLER__)
  end

  defmacro keyed_stub(key, expr) do
    do_keyed(key, expr, __CALLER__)
  end

  defp do_keyed(key, body, env) do
    {current_vars, _} = env.current_vars

    pre = fn
      {name, _opts, context} = var, acc
      when is_atom(name) and is_map_key(current_vars, {name, context}) ->
        {var, Map.put(acc, {name, context}, nil)}

      node, acc ->
        {node, acc}
    end

    post = fn
      _node, acc ->
        {nil, acc}
    end

    {_node, active_vars} = Macro.traverse(body, %{}, pre, post)

    active_vars_expr =
      active_vars
      |> Map.keys()
      |> Enum.map(fn {name, ctx} -> {name, [], ctx} end)

    quote do
      %Phoenix.DataView.Tracked.Tree.Keyed{
        id: {unquote(context_var), unquote(fragment_var)},
        key: unquote(key),
        escapes: unquote(active_vars_expr),
        render: fn ->
          unquote(body)
        end
      }
    end
  end

  # Utils
  
  def traverse_clauses(clauses, state, pre, post) do
    clauses
    |> Enum.map_reduce(state, fn {opts, args, [], ast}, state ->
      {ast, state} = Macro.traverse(ast, state, pre, post)
      {{opts, args, [], ast}, state}
    end)
  end

  def traverse_identity(node, state) do
    {node, state}
  end

  @context_var Macro.unique_var(:scope_id, __MODULE__)
  def context_var do
    @context_var
  end

  @fragment_var Macro.unique_var(:fragment_id, __MODULE__)
  def fragment_var do
    @fragment_var
  end
end
