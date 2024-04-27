defmodule LiveData.Tracked.TraceCollector do
  use GenServer

  @trace_key_pd_key :livedata_traced_trace_key

  def ensure_started do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def trace_module(pid, module, in_test \\ false) do
    :ok = GenServer.call(pid, {:trace_selector, {:module, module}, in_test})
  end

  def with_trace({_module, _function, _arity} = mfa, inner) do
    pid = Process.whereis(__MODULE__)
    with_trace(pid, mfa, inner)
  end

  def with_trace(nil, _mfa, inner) do
    trace_key = nil
    Process.put(@trace_key_pd_key, trace_key)
    inner.(trace_key)
  end

  def with_trace(pid, {_module, _function, _arity} = mfa, inner) do
    {:ok, {^pid, mfa} = trace_key} = GenServer.call(pid, {:begin_trace, mfa})
    Process.put(@trace_key_pd_key, trace_key)

    try do
      inner.(trace_key)
    after
      :ok = GenServer.call(pid, {:end_trace, mfa})
    end
  end

  def fetch_trace_key! do
    case Process.get(@trace_key_pd_key, :none) do
      :none -> raise "no trace key in process dictionary"
      key -> key
    end
  end

  def in_test? do
    in_test?(fetch_trace_key!())
  end

  def in_test?(nil) do
    false
  end

  def in_test?({pid, mfa}) do
    {:ok, in_test} = GenServer.call(pid, {:is_in_test, mfa})
    in_test
  end

  def log(tag, data) do
    log(fetch_trace_key!(), tag, data)
  end

  def log(nil, _tag, _data) do
    :ok
  end

  def log({pid, mfa} = _trace_key, tag, data) do
    :ok = GenServer.cast(pid, {:log, mfa, tag, data})
  end

  def get_module_traces(module) do
    GenServer.call(__MODULE__, {:get_module_traces, module})
  end

  def get_trace(mfa) do
    GenServer.call(__MODULE__, {:get_trace, mfa})
  end

  defstruct selectors: %{},
            traces: %{}

  defmodule Trace do
    defstruct mfa: nil,
              finished: false,
              in_test: false,
              log: []
  end

  @impl true
  def init(nil) do
    {:ok, %__MODULE__{}}
  end

  def update_trace(state, mfa, inner) do
    update_in(state.traces[mfa], inner)
  end

  def get_selector_data(state, {module, _f, _a} = mfa) do
    with :error <- Map.fetch(state.selectors, {:module, module}),
         :error <- Map.fetch(state.selectors, {:mfa, mfa}) do
      :error
    end
  end

  def trace_to_out(%Trace{} = trace) do
    %{
      mfa: trace.mfa,
      log: Enum.reverse(trace.log)
    }
  end

  @impl true
  def handle_call({:trace_selector, selector, in_test}, _from, state) do
    state = %{state | selectors: Map.put(state.selectors, selector, in_test)}
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:begin_trace, mfa}, _from, state) do
    traced = get_selector_data(state, mfa)

    case traced do
      {:ok, in_test} ->
        state = %{
          state
          | traces:
              Map.put(state.traces, mfa, %Trace{
                in_test: in_test,
                mfa: mfa
              })
        }

        {:reply, {:ok, {self(), mfa}}, state}

      :error ->
        {:reply, {:ok, nil}, state}
    end
  end

  @impl true
  def handle_call({:end_trace, mfa}, _from, state) do
    state =
      update_trace(state, mfa, fn trace ->
        %{trace | finished: true}
      end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:is_in_test, mfa}, _from, state) do
    traced = get_selector_data(state, mfa)
    {:reply, traced, state}
  end

  @impl true
  def handle_call({:get_trace, mfa}, _from, state) do
    case Map.fetch(state.traces, mfa) do
      {:ok, %{finished: true} = trace} ->
        {:reply, {:ok, trace_to_out(trace)}, state}

      {:ok, %{finished: false}} ->
        {:reply, {:error, :not_finished}, state}

      :error ->
        {:reply, {:error, :not_traced}, state}
    end
  end

  @impl true
  def handle_call({:get_module_traces, module}, _module, state) do
    out =
      state.traces
      |> Enum.flat_map(fn
        {{^module, _f, _a} = mfa, trace} ->
          [{mfa, trace_to_out(trace)}]

        _ ->
          []
      end)
      |> Enum.into(%{})

    {:reply, {:ok, out}, state}
  end

  @impl true
  def handle_cast({:log, mfa, tag, data}, state) do
    state =
      update_trace(state, mfa, fn trace ->
        %{trace | log: [{tag, data} | trace.log]}
      end)

    {:noreply, state}
  end
end
