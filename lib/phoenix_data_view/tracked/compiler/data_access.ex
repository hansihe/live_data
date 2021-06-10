defmodule Phoenix.DataView.Tracked.Compiler.DataAccess do

  alias Phoenix.DataView.Tracked.Compiler.Dataflow

  def data_access_for(%Dataflow{} = dataflow, {:comp, _} = comp) do

    dependents =
      dataflow.argument_roots
      |> Enum.with_index()
      |> Enum.map(fn {idx, root} -> {root, {:arg, idx}} end)
      |> Enum.into(%{})

    state = %{
      pending: dataflow.argument_roots,
      finished: %{},
      dataflow: dataflow,
      dependents: dependents
    }

    visited = MapSet.new([comp])

    visited =
      case Dataflow.get_equation(comp, dataflow) do
        {:call, _opts, _fun, args} ->
          Enum.reduce(args, visited, fn arg, state ->
            dependency_scope(dataflow, arg, visited)
          end)
      end

    IO.inspect visited

    state
  end

  def dependency_scope(dataflow, comp, acc) do
    if MapSet.member?(acc, comp) do
      acc
    else
      acc = MapSet.put(acc, comp)

      comp
      |> Dataflow.get_equation(dataflow)
      |> get_incoming()
      |> Enum.reduce(acc, fn comp, acc ->
        dependency_scope(dataflow, comp, acc)
      end)
    end
  end

  def iter(%{pending: [item | items_tail], finished: finished} = state) when is_map_key(finished, item) do
    iter(%{state | pending: items_tail})
  end

  def iter(%{pending: [item | items]} = state) do
    iter(%{state | pending: items})
  end

  def iter(%{pending: []} = state) do
    state
  end

  def get_incoming({:argument, _opts}) do
    []
  end
  def get_incoming({:call, _opts, _fun, args}) do
    args
  end
  def get_incoming({:fetch_map, _opts, map, static_field}) when is_atom(static_field) do
    [map]
  end
  def get_incoming({:iter, _opts, _loop, value}) do
    [value]
  end
  def get_incoming({:make_map, _opts, nil, kvs}) do
    Enum.flat_map(kvs, fn {k, v} -> [k, v] end)
  end
  def get_incoming({:literal, _opts, _typ, _value}) do
    []
  end
  def get_incoming({:collect_list, _opts, _loop, value}) do
    [value]
  end

end
