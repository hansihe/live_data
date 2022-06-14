defmodule LiveData.Tracked.KeyedException do
  @moduledoc """
  This exception is thrown if the user is not consistent with their
  key => value mapping within a deft.
  """

  defexception mfa: nil, line: nil, previous: nil, next: nil

  @impl true
  def message(_value) do
    "keyed must strictly adhere to a key => value mapping"
  end
end
