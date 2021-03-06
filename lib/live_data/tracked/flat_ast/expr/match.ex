defmodule LiveData.Tracked.FlatAst.Expr.Match do
  @moduledoc false

  defstruct pattern: nil, binds: nil, rhs: nil, location: nil

  def new(pattern, binds, rhs, location \\ nil) do
    %__MODULE__{
      pattern: pattern,
      binds: binds,
      rhs: rhs,
      location: location
    }
  end
end
