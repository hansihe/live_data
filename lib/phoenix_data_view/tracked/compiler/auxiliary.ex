defmodule Phoenix.DataView.Tracked.Compiler.Auxiliary do
  @moduledoc """
  Generates auxiliary information for the base dataflow IR.
  """

  alias Phoenix.DataView.Tracked.Compiler.Dataflow

  defstruct dataflow: nil,
    reverse: nil,
    all_set: nil,
    forward_set: nil,
    reverse_set: nil

  def new(dataflow) do
    %__MODULE__{
      dataflow: dataflow
    }
  end

  @doc """
  Calculates the reverse map for a set of dataflow equations.

  In it's native form, the dataflow equations are written in the form
  `out => f(in)`. This means walking the computation graph from the result is
  cheap and easy.

  Walking from the inputs (arguments) to the outputs is not easy in their native
  form.

  The reverse map provides a mapping of `in = [out1, out2, ..]`, making it easy
  to walk the computation graph in the forward direction.
  """
  def calc_reverse(%__MODULE__{} = aux) do
    dataflow = aux.dataflow

    put_reverse = fn
      state, from, tos ->
        Enum.reduce(tos, state, fn {:comp, to}, state ->
          Map.update!(state, to, &MapSet.put(&1, from))
        end)
    end

    reverse =
      dataflow.equations
      |> Enum.map(fn {id, _body} -> {id, MapSet.new()} end)
      |> Enum.into(%{})

    reverse =
      Enum.reduce(dataflow.equations, reverse, fn
        {id, eq}, acc ->
          put_reverse.(acc, id, Dataflow.get_incoming(eq))
      end)

    %{aux | reverse: reverse}
  end

  @doc """
  Calculates the cumulative dependency sets for a set of dataflow equations.
  """
  def calc_depsets(%__MODULE__{} = aux) do
    dataflow = aux.dataflow

    base_depsets =
      Enum.into(Enum.map(dataflow.equations, fn {id, _body} -> {id, MapSet.new()} end), %{})

    forward_depsets =
      Enum.reduce(dataflow.argument_roots, base_depsets, fn id, acc ->
        calc_depsets_rec(id, MapSet.new(), acc, fn id ->
          Map.fetch!(aux.reverse, id)
          |> Enum.map(&{:comp, &1})
        end)
      end)

    reverse_depsets =
      calc_depsets_rec(dataflow.result, MapSet.new(), base_depsets, fn id ->
        equation = Map.fetch!(dataflow.equations, id)
        Dataflow.get_incoming(equation)
      end)

    all_set = Enum.reduce(dataflow.equations, MapSet.new(), fn {id, _body}, acc ->
      MapSet.put(acc, id)
    end)

    %{aux | forward_set: forward_depsets, reverse_set: reverse_depsets, all_set: all_set}
  end

  defp calc_depsets_rec({:comp, id}, current, acc, query) do
    acc = update_in(acc[id], &MapSet.union(&1, current))

    next = query.(id)
    current = MapSet.put(current, id)

    Enum.reduce(next, acc, &calc_depsets_rec(&1, current, &2, query))
  end

end
