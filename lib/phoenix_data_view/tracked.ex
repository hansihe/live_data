defmodule Phoenix.DataView.Tracked do
  alias Phoenix.DataView.Tracked
  alias Phoenix.DataView.Tracked.Compiler
  alias Phoenix.DataView.Tracked.Util

  @type tree :: any()

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
    descr = Macro.escape({__CALLER__.module, {name, args_count}})

    quote do
      @phoenix_data_view_tracked unquote(descr)
      unquote(make_main_fun(:def, call, body, __CALLER__))
    end
  end

  defmacro defpt(call, do: body) do
    {name, args} = Util.decompose_call!(:defp, call, __CALLER__)
    args_count = Enum.count(args)
    descr = Macro.escape({__CALLER__.module, {name, args_count}})

    quote do
      @phoenix_data_view_tracked unquote(descr)
      unquote(make_main_fun(:defp, call, body, __CALLER__))
    end
  end

  defmacro __before_compile__(env) do
    functions =
      env.module
      |> Module.get_attribute(:phoenix_data_view_tracked)
      |> Enum.map(fn val -> {val, nil} end)
      |> Enum.into(%{})
      |> Map.keys()

    for {module, name} <- functions do
      define(module, name)
    end
  end

  defp define(module, {name, arity} = fun) do
    {:v1, kind, meta, clauses} = Tracked.Module.get_definition(module, fun)

    compiled = Compiler.compile(module, fun, kind, meta, clauses)

    quote do
      Phoenix.DataView.Tracked.Module.delete_definition(unquote(module), unquote(fun))
      unquote(compiled)
    end
  end

  defp make_main_fun(kind, call, body, env) do
    wrapped_body =
      quote do
        import Phoenix.DataView.Tracked.Dummy, only: [keyed: 2, track: 1]
        unquote(body)
      end

    {kind, [line: env.line], [call, [do: wrapped_body]]}
  end
end
