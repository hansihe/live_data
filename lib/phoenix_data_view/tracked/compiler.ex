defmodule Phoenix.DataView.Tracked.Compiler do
  alias Phoenix.DataView.Tracked.Compiler
  alias Phoenix.DataView.Tracked.Compiler2
  alias Phoenix.DataView.Tracked.Dummy
  alias Phoenix.DataView.Tracked.FlatAst
  alias Phoenix.DataView.Tracked.Util

  def compile(module, {name, arity} = fun, kind, meta, clauses) do
    ids_fun_name = String.to_atom("__tracked_ids_#{name}_#{arity}__")
    tracked_fun_name = String.to_atom("__tracked_#{name}__")

    {:ok, ast} = FlatAst.FromAst.from_clauses(clauses)
    ast = FlatAst.Pass.Normalize.normalize(ast)

    nesting = FlatAst.Pass.CalculateNesting.calculate_nesting(ast)

    # TODO we might not want to do it this way
    nesting_set =
      nesting
      |> Enum.map(fn {expr, path} ->
        Enum.map(path, &{&1, expr})
      end)
      |> Enum.concat()
      |> Enum.into(MapSet.new())

    #expr = FlatAst.ToAst.to_expr(ast, pretty: true)
    #tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)
    #IO.puts Macro.to_string(tracked_defs)

    {:ok, new_ast} = FlatAst.Pass.RewriteAst.rewrite(ast, nesting_set)
    #IO.inspect new_ast

    expr = FlatAst.ToAst.to_expr(new_ast, pretty: true)
    #tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)
    #IO.puts Macro.to_string(tracked_defs)

    tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)


    ### true = false

    ### uses_count = FlatAst.Pass.CountUses.count_uses(ast)
    ### IO.inspect uses_count

    ### expr = FlatAst.ToAst.to_expr(ast, pretty: true)
    ### tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)
    ### IO.puts Macro.to_string(tracked_defs)

    ### FlatAst.Pass.RewriteAst.rewrite(ast)

    ### true = false

    ### scopes = FlatAst.Pass.IdentifyScopes.identify_scopes(ast)
    ### {ast, statics} = FlatAst.Pass.ExtractStatic.extract_static(ast, uses_count, scopes)

    ### expr = FlatAst.ToAst.to_expr(ast, pretty: true)
    ### tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)
    ### #IO.inspect tracked_defs
    ### IO.puts Macro.to_string(tracked_defs)

    ### true = false

    ### expr = FlatAst.ToAst.to_expr(ast)


    ### tracked_defs = Util.fn_to_defs(expr, tracked_fun_name)
    ### IO.inspect tracked_defs
    ### IO.puts Macro.to_string(tracked_defs)

    # true = false

    # {:ok, ir} = Compiler2.FromAst.from_clauses(clauses)
    # Compiler2.ToAst.to_ast(ir)

    # true = false

    # clauses = Compiler.AssignNodeIds.assign_node_ids(clauses)
    # dataflow = Compiler.FromAst.from_clauses(clauses)

    # {statics, dataflow} = Compiler.ExtractStatic.extract_static(dataflow)

    # aux =
    #   dataflow
    #   |> Compiler.Auxiliary.new()
    #   |> Compiler.Auxiliary.calc_reverse()
    #   |> Compiler.Auxiliary.calc_depsets()

    # IO.inspect Compiler.Synthesize.synthesize(aux)

    # keyed_ids =
    #   dataflow.equations
    #   |> Enum.filter(fn
    #     {_id, {:call, _opts, {Phoenix.DataView.Tracked.Dummy, :keyed_stub}, _}} ->
    #       true

    #     _ ->
    #       false
    #   end)
    #   |> Enum.map(fn {id, _val} -> id end)

    # Enum.map(keyed_ids, &Compiler.DataAccess.data_access_for(dataflow, {:comp, &1}))

    # {clauses, ids_state} = assign_fragment_ids(module, clauses)

    [
      make_normal_fun(kind, fun, clauses),
      tracked_defs
      #make_ids_fun(module, kind, ids_fun_name, fun, ids_state),
      #make_tracked_fun(module, kind, tracked_fun_name, fun, clauses)
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


  # Tracked function

  def make_tracked_fun(module, kind, name, {orig_name, orig_arity}, clauses) do
    clauses = rewrite_ast_tracked(module, orig_name, orig_arity, clauses)

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

  def rewrite_ast_tracked(module, name, arity, clauses) do
    post = fn node, nil ->
      case Macro.decompose_call(node) do
        {Dummy, :keyed_stub, args} ->
          {_, opts, _} = node
          fragment_id = Keyword.fetch!(opts, :tracked_id)

          block =
            quote do
              unquote(fragment_var()) = unquote(fragment_id)
              unquote(__MODULE__).keyed_stub(unquote_splicing(args))
            end

          {block, nil}

        {Dummy, :track_stub, args} ->
          block =
            quote do
              unquote(__MODULE__).track_stub(unquote_splicing(args))
            end

          {block, nil}

        _ ->
          {node, nil}
      end
    end

    {clauses, nil} = traverse_clauses(clauses, nil, &traverse_identity/2, post)

    for {opts, args, [], body} <- clauses do
      body =
      quote do
        require(unquote(__MODULE__))
        unquote(context_var) = {unquote(module), unquote(name), unquote(arity)}
        unquote(body)
      end

      {opts, args, [], body}
    end
  end

  # Assign fragment IDs prepass

  def assign_fragment_ids(module, clauses) do
    state = %{
      fragment_lines: %{},
      tracked_calls: [],
      counter: 0
    }

    pre = fn node, state ->
      case Macro.decompose_call(node) do
        {Dummy, :keyed_stub, args} ->
          {target, opts, args} = node
          line = Keyword.get(opts, :line)

          node = {target, [{:tracked_id, state.counter} | opts], args}

          state = %{
            state
            | fragment_lines: Map.put(state.fragment_lines, state.counter, line),
              counter: state.counter + 1
          }

          {node, state}

        {Dummy, :track_stub, args} ->
          [call] = args

          case Macro.decompose_call(call) do
            {module, name, args} ->
              args_count = Enum.count(args)
              state = %{state | tracked_calls: [{module, name, args_count} | state.tracked_calls]}
              {node, state}

            {name, args} ->
              args_count = Enum.count(args)
              state = %{state | tracked_calls: [{module, name, args_count} | state.tracked_calls]}
              {node, state}
          end

        _ ->
          {node, state}
      end
    end

    {clauses, state} = traverse_clauses(clauses, state, pre, &traverse_identity/2)

    {clauses, state}
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
