defmodule LiveData.Tracked do
  @moduledoc """
  This module contains implementations for the `deft` macros used
  to define tracked functions.

  `use` this module directly if you are defining `deft` functions
  outside of a LiveData module.

  This module is `use`d automatically when doing `use LiveData`
  """

  alias LiveData.Tracked.Compiler
  alias LiveData.Tracked.Util

  @type tree :: any()

  defmacro __using__(_opts) do
    quote do
      @before_compile LiveData.Tracked
      :ok = Module.register_attribute(__MODULE__, :phoenix_data_view_tracked, accumulate: true)
      import LiveData.Tracked, only: [deft: 2, defpt: 2]
    end
  end

  defmacro deft(call, do: body) do
    {name, args} = Util.decompose_call!(:def, call, __CALLER__)
    args_count = Enum.count(args)
    descr = Macro.escape({__CALLER__.module, {name, args_count}})

    quote do
      unquote(__MODULE__).validate_used!(unquote(__CALLER__.file), unquote(__CALLER__.module), unquote(__CALLER__.line))
      @phoenix_data_view_tracked unquote(descr)
      unquote(make_main_fun(:def, call, body, __CALLER__))
    end
  end

  defmacro defpt(call, do: body) do
    {name, args} = Util.decompose_call!(:defp, call, __CALLER__)
    args_count = Enum.count(args)
    descr = Macro.escape({__CALLER__.module, {name, args_count}})

    quote do
      unquote(__MODULE__).validate_used!(unquote(__CALLER__.file), unquote(__CALLER__.module), unquote(__CALLER__.line))
      @phoenix_data_view_tracked unquote(descr)
      unquote(make_main_fun(:defp, call, body, __CALLER__))
    end
  end

  defmacro __before_compile__(env) do
    file = env.file

    functions =
      env.module
      |> Module.get_attribute(:phoenix_data_view_tracked)
      |> Enum.map(fn val -> {val, nil} end)
      |> Enum.into(%{})
      |> Map.keys()

    for {module, name} <- functions do
      define(module, file, name)
    end
  end

  def validate_used!(file, module, line) do
    unless Module.has_attribute?(module, :phoenix_data_view_tracked) do
      throw %CompileError{
        file: file,
        line: line,
        description: "`LiveData.Tracked` must be `use`d before calling `deft`"
      }
    end
  end

  defp define(module, file, {_name, _arity} = fun) do
    {:v1, kind, meta, clauses} = Elixir.Module.get_definition(module, fun)

    compiled = Compiler.compile(module, file, fun, kind, meta, clauses)

    quote do
      Elixir.Module.delete_definition(unquote(module), unquote(fun))
      unquote(compiled)
    end
  end

  defp make_main_fun(kind, call, body, env) do
    #IO.inspect Macro.Env.lookup_import(env, {:keyed, 2}), label: :lookup_import

    wrapped_body =
      quote do
        import LiveData.Tracked.Dummy, only: [keyed: 2, track: 1, hook: 1, hook: 2, custom_fragment: 1]
        unquote(body)
      end

    {kind, [line: env.line], [call, [do: wrapped_body]]}
  end
end
