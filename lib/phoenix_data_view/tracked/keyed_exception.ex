defmodule Phoenix.DataView.Tracked.KeyedException do
  defexception mfa: nil, line: nil, previous: nil, next: nil

  @impl true
  def message(_value) do
    "keyed must strictly adhere to a key => value mapping"
  end
end
