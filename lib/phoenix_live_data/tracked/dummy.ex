defmodule LiveData.Tracked.Dummy do

  defp make_tracked_fn_atom_ast(name) when is_atom(name) do
    atom_str = "__tracked__#{Atom.to_string(name)}__"
    String.to_atom(atom_str)
  end

  defmacro track(call) do
    req =
      case call do
        {local_fun, opts, args} when is_atom(local_fun) ->
          tracked_fn = make_tracked_fn_atom_ast(local_fun)
          {tracked_fn, opts, args}

        {{:., path_opts, [module, fun_name]}, opts, args} when is_atom(fun_name) ->
          tracked_fn = make_tracked_fn_atom_ast(fun_name)
          {{:., path_opts, [module, tracked_fn]}, opts, args}

        _ ->
          raise CompileError,
            file: __CALLER__.file,
            line: __CALLER__.line,
            description: "tracked macro must directly surround function call"
      end

    quote do
      unquote(__MODULE__).track_stub(unquote(req))
    end
  end

  defmacro keyed(key, do: body) do
    quote do
      unquote(__MODULE__).keyed_stub(unquote(key), unquote(body))
    end
  end

  defmacro keyed(key, expr) do
    quote do
      unquote(__MODULE__).keyed_stub(unquote(key), unquote(expr))
    end
  end

  @doc false
  def keyed_stub(_key, _expr) do
    raise "unreachable"
  end

  @doc false
  def track_stub(_inner) do
    raise "unreachable"
  end

end
