ExUnit.start()

defmodule LiveData.Tracked.TestHelpers do

  def try_define_module_ast(ast, opts) do
    try do
      unique_id = :erlang.unique_integer([:positive])
      module_name = String.to_atom("Elixir.LiveData.Tracked.TestModule#{unique_id}")

      {:module, ^module_name, _binary, _term} = Module.create(module_name, ast, opts)

      {:ok, module_name}
    rescue
      e ->
        {:error, e, __STACKTRACE__}
    end
  end

  defmacro try_define_module(do: body) do
    location = Macro.Env.location(__CALLER__)
    body_escaped = Macro.escape(body)
    quote do
      try_define_module_ast(unquote(body_escaped), unquote(location))
    end
  end

end
