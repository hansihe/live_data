defmodule LiveData.Tracked.LifecycleHook do
  @moduledoc """
  Behaviour for a module which can be used with `lifecycle_hook` in a `custom_fragment`.

  This enables you to maintain state for the given "location" in the template, identified by
  the nearest parent `keyed`.
  """

  @type rendered :: any()
  @type subtrees :: [rendered()]

  @type state :: any()
  @type socket :: any()

  @callback on_enter(subtrees(), socket()) :: {rendered(), state(), socket()}
  @callback on_update(subtrees(), state(), socket()) :: {rendered(), state(), socket()}
  @callback on_exit(state(), socket()) :: {state(), socket()}

end
