ExUnit.start()

defmodule LiveData.Tracked.TestHelpers do
  alias LiveData.Tracked.TraceCollector

  def define_module_ast!(ast, opts, print_trace \\ false) do
    unique_id = :erlang.unique_integer([:positive])
    module_name = String.to_atom("Elixir.LiveData.Tracked.TestModule#{unique_id}")

    {:ok, trace_collector_pid} = TraceCollector.ensure_started()
    :ok = TraceCollector.trace_module(trace_collector_pid, module_name, true)

    {:module, ^module_name, _binary, _term} = try do
      out = Module.create(module_name, ast, opts)

      if print_trace do
        {:ok, traces} = TraceCollector.get_module_traces(module_name)
        IO.puts(inspect(traces, limit: :infinity))
      end

      out
    rescue
      e ->
        {:ok, traces} = TraceCollector.get_module_traces(module_name)
        IO.puts(inspect(traces, limit: :infinity))

        reraise e, __STACKTRACE__
    end


    module_name
  end

  def try_define_module_ast(ast, opts) do
    unique_id = :erlang.unique_integer([:positive])
    module_name = String.to_atom("Elixir.LiveData.Tracked.TestModule#{unique_id}")

    {:ok, trace_collector_pid} = TraceCollector.ensure_started()
    :ok = TraceCollector.trace_module(trace_collector_pid, module_name, true)

    try do
      {:module, ^module_name, _binary, _term} = Module.create(module_name, ast, opts)

      {:ok, traces} = TraceCollector.get_module_traces(module_name)
      {:ok, module_name, traces}
    rescue
      e ->
        {:ok, traces} = TraceCollector.get_module_traces(module_name)
        {:error, module_name, traces, e, __STACKTRACE__}
    end
  end

  defmacro try_define_module(do: body) do
    location = Macro.Env.location(__CALLER__)
    body_escaped = Macro.escape(body)
    quote do
      try_define_module_ast(unquote(body_escaped), unquote(location))
    end
  end

  defmacro define_module!(opts \\ [], do: body) do
    print_trace = Keyword.get(opts, :print_trace, false)

    location = Macro.Env.location(__CALLER__)
    body_escaped = Macro.escape(body)

    quote do
      define_module_ast!(unquote(body_escaped), unquote(location), unquote(print_trace))
    end
  end

end
