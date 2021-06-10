defmodule Phoenix.DataView.Tracked.Compiler.InferStatic do
  alias Phoenix.DataView.Tracked.Compiler.Dataflow

  def infer_static(dataflow) do
    state = []
    IO.inspect(infer_static_rec(dataflow.result, state, dataflow))
  end

  def infer_static_rec(eq_id, state, df) do
    case Dataflow.get_equation(eq_id, df) do
      {:match_join, _opts, clauses} ->
        Enum.reduce(clauses, state, fn clause_eq_id, state ->
          {ret, state} = infer_static_rec(clause_eq_id, state, df)
          state = [ret | state]
          state
        end)

      {:make_map, _opts, nil, entries} ->
        {kvs, state} =
          entries
          |> Enum.map_reduce(state, fn {key, val}, state ->
            {key_ret, state} = infer_static_rec(key, state, df)
            {val_ret, state} = infer_static_rec(val, state, df)
            {{key_ret, val_ret}, state}
          end)
        {Enum.into(kvs, %{}), state}

      {:literal, _opts, :atom, atom} ->
        {atom, state}

      {:collect_list, _opts, _loop_id, inner} ->
        {ret, state} = infer_static_rec(inner, state, df)
        state = [ret | state]
        {eq_id, state}

      any ->
        IO.inspect any
        {{:embed, eq_id}, state}
    end
  end

end
