ExUnit.start()

:erlang.system_flag(:backtrace_depth, 20)

defmodule LiveData.Tracked.SmartEngineWrapper do
  def handle_begin(state), do: EEx.SmartEngine.handle_begin(state)
  def handle_body(state, _opts \\ []) do
    body_ast = EEx.SmartEngine.handle_body(state)
    #quote do
    #  unquote(body_ast)
    #  #LiveData.Tracked.Dummy.marker_stub(:html, outer_body)
    #end
    body_ast
  end
  def handle_end(state), do: EEx.SmartEngine.handle_end(state)
  def handle_expr(state, marker, expr), do: EEx.SmartEngine.handle_expr(state, marker, expr)
  def handle_text(state, list, text), do: EEx.SmartEngine.handle_text(state, list, text)
  def init(opts), do: EEx.SmartEngine.init(opts)
end

defmodule LiveData.Tracked.TestHelpers do
  alias LiveData.Tracked.TraceCollector

  defmacro sigil_H({:<<>>, meta, [expr]}, modifiers)
           when modifiers == [] or modifiers == ~c"noformat" do
    if not Macro.Env.has_var?(__CALLER__, {:assigns, nil}) do
      raise "~H requires a variable named \"assigns\" to exist and be set to a map"
    end

    options = [
      engine: Phoenix.LiveView.TagEngine,
      subengine: LiveData.Tracked.SmartEngineWrapper,
      file: __CALLER__.file,
      line: __CALLER__.line + 1,
      caller: __CALLER__,
      indentation: meta[:indentation] || 0,
      source: expr,
      tag_handler: Phoenix.LiveView.HTMLEngine
    ]

    EEx.compile_string(expr, options)
  end

  def define_module_ast!(ast, opts, print_trace \\ false) do
    unique_id = :erlang.unique_integer([:positive])
    module_name = String.to_atom("Elixir.LiveData.Tracked.TestModule#{unique_id}")

    {:ok, trace_collector_pid} = TraceCollector.ensure_started()
    :ok = TraceCollector.trace_module(trace_collector_pid, module_name, true)

    {:module, ^module_name, _binary, _term} =
      try do
        out = Module.create(module_name, ast, opts)

        if print_trace do
          {:ok, traces} = TraceCollector.get_module_traces(module_name)
          IO.puts(inspect(traces, pretty: true, limit: :infinity))
        end

        out
      rescue
        e ->
          {:ok, traces} = TraceCollector.get_module_traces(module_name)
          IO.puts(inspect(traces, pretty: true, limit: :infinity))

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
