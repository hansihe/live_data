defmodule LiveData.Tracked.Aliases do
  @moduledoc false

  defstruct next_id: 0, ids: %{}

  def new do
    %__MODULE__{}
  end

  def alias_for(data, %__MODULE__{next_id: id, ids: ids} = state) do
    case Map.fetch(ids, data) do
      {:ok, id} ->
        {id, state}

      :error ->
        state = %__MODULE__{
          next_id: id + 1,
          ids: Map.put(ids, data, id)
        }
        {id, state}
    end
  end
end
