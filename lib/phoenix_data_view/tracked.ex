defmodule Phoenix.DataView.Tracked do
  alias Phoenix.DataView.Tracked.Util
  alias Phoenix.DataView.Tracked.Compiler

  @type state :: any()

  defmacro __using__(_opts) do
    quote do
      @before_compile Phoenix.DataView.Tracked
      :ok = Module.register_attribute(__MODULE__, :phoenix_data_view_tracked, accumulate: true)
      import Phoenix.DataView.Tracked, only: [deft: 2, defpt: 2]
    end
  end

  defmacro deft(call, do: body) do
    {name, args} = Util.decompose_call!(:def, call, __CALLER__)
    args_count = Enum.count(args)
    descr = Macro.escape({:def, {name, args, args_count}, call, body, __CALLER__})

    quote do
      @phoenix_data_view_tracked unquote(descr)
    end
  end

  defmacro defpt(call, do: body) do
    {name, args} = Util.decompose_call!(:defp, call, __CALLER__)
    args_count = Enum.count(args)
    descr = Macro.escape({:defp, {name, args, args_count}, call, body, __CALLER__})

    quote do
      @phoenix_data_view_tracked unquote(descr)
    end
  end

  defmacro __before_compile__(env) do
    clauses = Module.get_attribute(env.module, :phoenix_data_view_tracked)
    functions = Enum.group_by(clauses, fn {_, {name, _, count}, _, _, _} -> {name, count} end)

    for {shape, funs} <- functions do
      define(shape, funs)
    end
  end

  defp define({name, args_count}, [{kind, {_, args, _}, call, body, env}]) do
    {body, fragment_state} = assign_fragment_ids(body, env)

    [
      make_main_fun(kind, call, body, env),
      make_ids_fun(kind, call, name, args, args_count, body, env, fragment_state),
      make_tracked_fun(kind, call, name, args, args_count, body, env)
    ]
  end

  defp make_main_fun(kind, call, body, env) do
    wrapped_body =
      quote do
        import Phoenix.DataView.Tracked.Dummy, only: [keyed: 2, track: 1]
        unquote(body)
      end

    {kind, [line: env.line], [call, [do: wrapped_body]]}
  end

  defp make_ids_fun(kind, call, name, args, args_count, body, env, fragment_state) do
    ids_fun_name = String.to_atom("__tracked_ids_#{name}_#{args_count}__")

    args = Macro.generate_arguments(1, __MODULE__)
    header_call = {ids_fun_name, [], args}

    [state_var] = args

    num_ids = fragment_state.counter

    body =
      quote do
        scope_id = {unquote(env.module), unquote(name), unquote(args_count)}

        if Map.has_key?(unquote(state_var).visited, scope_id) do
          unquote(state_var)
        else
          %{ids: ids, visited: visited, counter: counter} = unquote(state_var)
          visited = Map.put(visited, scope_id, nil)

          ids =
            unquote(
              fragment_state.fragment_lines
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
            )

          state = %{
            unquote(state_var)
            | ids: ids,
              visited: visited,
              counter: counter + unquote(num_ids)
          }

          unquote(
            fragment_state.tracked_calls
            |> Enum.map(fn {module, name, arity} ->
              ids_fun_name = String.to_atom("__tracked_ids_#{name}_#{args_count}__")

              quote do
                state = unquote(ids_fun_name)(state)
              end
            end)
          )

          state
        end
      end

    {kind, [], [header_call, [do: body]]}
  end

  defp make_tracked_fun(kind, call, name, args, args_count, body, env) do
    tracked_fun_name = String.to_atom("__tracked_#{name}__")

    header_args = args
    header_call = {tracked_fun_name, [], header_args}

    tracked_body =
      quote do
        import Phoenix.DataView.Tracked.Compiler, only: [keyed: 2, track: 1]

        unquote(Compiler.context_var()) =
          {unquote(env.module), unquote(name), unquote(args_count)}

        unquote(body)
      end

    [
      {kind, [line: env.line], [header_call, [do: tracked_body]]}
    ]
  end

  def assign_fragment_ids(ast, env) do
    pre = fn node, acc -> {node, acc} end

    state = %{
      fragment_lines: %{},
      tracked_calls: [],
      counter: 0
    }

    post = fn
      {:keyed, opts, inner}, state ->
        block =
          quote do
            unquote(Compiler.fragment_var()) = unquote(state.counter)
            unquote({:keyed, opts, inner})
          end

        line = Keyword.get(opts, :line)

        state = %{
          state
          | fragment_lines: Map.put(state.fragment_lines, state.counter, line),
            counter: state.counter + 1
        }

        {block, state}

      {:track, opts, inner} = ast, state ->
        [inner] = inner

        case Macro.decompose_call(inner) do
          {name, args} ->
            args_count = Enum.count(args)

            state = %{
              state
              | tracked_calls: [{env.module, name, args_count} | state.tracked_calls]
            }

            {ast, state}

          {module, name, args} ->
            args_count = Enum.count(args)

            state = %{
              state
              | tracked_calls: [{name, args_count} | state.tracked_calls]
            }

            {ast, state}

          :error ->
            raise CompileError, "TODO error"
        end

      any, state ->
        {any, state}
    end

    {ast, state} = Macro.traverse(ast, state, pre, post)

    state = %{
      state
      | fragment_lines: Enum.reverse(state.fragment_lines)
    }

    {ast, state}
  end
end
