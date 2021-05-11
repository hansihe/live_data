defmodule FlutterView do

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__), only: [
        scaffold: 1,
        app_bar: 1,
        text: 1,
        list_view: 1,
        floating_action_button: 1
      ]
    end
  end

  def maybe_put(map, _key, nil) do
    map
  end
  def maybe_put(map, key, value) do
    Map.put(map, key, value)
  end

  defmacro scaffold(items) do
    quote do
      app_bar = unquote(Keyword.get(items, :app_bar))
      body = unquote(Keyword.get(items, :body))
      fab = unquote(Keyword.get(items, :floating_action_button))

      %{t: "scaffold"}
      |> FlutterView.maybe_put(:app_bar, app_bar)
      |> FlutterView.maybe_put(:body, body)
      |> FlutterView.maybe_put(:fab, fab)
    end
  end

  defmacro app_bar(items) do
    quote do
      title = unquote(Keyword.get(items, :title))

      %{t: "app_bar"}
      |> FlutterView.maybe_put(:title, title)
    end
  end

  defmacro text(text) do
    quote do
      %{
        t: "text",
        text: unquote(text)
      }
    end
  end

  defmacro list_view(items) do
    quote do
      children = unquote(Keyword.get(items, :children))

      %{t: "list_view"}
      |> FlutterView.maybe_put(:children, children)
    end
  end

  defmacro floating_action_button(items) do
    quote do
      on_pressed_event = unquote(Keyword.get(items, :on_pressed_event))

      %{t: "fab"}
      |> FlutterView.maybe_put(:on_pressed_event, on_pressed_event)
    end
  end

end
