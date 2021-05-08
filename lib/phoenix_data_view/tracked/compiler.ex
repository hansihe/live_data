defmodule Phoenix.DataView.Tracked.Compiler do
  defstruct []

  defmacro track(call) do
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

  defmacro keyed(key, do: body) do
    do_keyed(key, body, __CALLER__)
  end

  defmacro keyed(key, expr) do
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
      %Phoenix.DataView.Tracked.Keyed{
        id: {unquote(context_var), unquote(fragment_var)},
        key: unquote(key),
        escapes: unquote(active_vars_expr),
        render: fn ->
          unquote(body)
        end
      }
    end
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
