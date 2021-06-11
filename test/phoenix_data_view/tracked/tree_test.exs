defmodule Phoenix.DataView.Tracked.TreeTest do
  use ExUnit.Case

  alias Phoenix.DataView.Tracked.Render
  alias Phoenix.DataView.Tracked.Apply
  alias Phoenix.DataView.Tracked.Diff
  alias Phoenix.DataView.Tracked.Tree

  use Phoenix.DataView.Tracked

  deft render(assigns) do
    %{
      categories:
        for category <- assigns.categories do
          keyed category.id do
            %{
              posts:
                for post <- category.posts do
                  keyed(post.id, track(render_post(post)))
                end
            }
          end
        end
    }
  end

  deft render_post(post) do
    %{
      title: post.title,
      text: post.text
    }
  end

  use FlutterView

  test "yay" do
    assigns = %{
      categories: [
        %{
          id: 0,
          posts: [
            %{
              id: 0,
              title: "woo",
              text: "hoo"
            }
          ]
        }
      ]
    }

    IO.inspect __tracked_meta__render__1__(:statics)

    out = __tracked__render__(assigns)
    IO.inspect out

    IO.inspect out.slots.()

    IO.inspect hd(hd(out.slots.())).slots.()

    IO.inspect hd(hd(hd(hd(out.slots.())).slots.())).slots.()
  end

  #deft flutter_view_test() do
  #  scaffold(
  #    app_bar: app_bar(
  #      title: text("hello world")
  #    ),
  #    body: list_view(
  #      children: [],
  #    ),
  #    floating_action_button: floating_action_button(
  #      on_pressed_event: "add_post"
  #    ),
  #  )
  #end

  # def proto__track_render2__(:make_ids, state) do
  #  scope_id = {__MODULE__, :render2, 1}

  #  if Map.has_key?(state.visited, scope_id) do
  #    state
  #  else
  #    %{ids: ids, visited: visited, counter: counter} = state
  #    visited = Map.put(visited, scope_id, nil)
  #    ids = Map.put(ids, {scope_id, 0}, %{num: counter + 0, line: 22})
  #    ids = Map.put(ids, {scope_id, 1}, %{num: counter + 1, line: 25})
  #    ids = Map.put(ids, {scope_id, 2}, %{num: counter + 2, line: 33})
  #    state = %{state | ids: ids, visited: visited, counter: counter + 3}

  #    state = proto__track_render_post__(:make_ids, state)
  #    state
  #  end
  # end

  # def proto__track_render2__(:render, assigns) do
  #  scope_id = {__MODULE__, :render2, 1}

  #  %Phoenix.DataView.Tracked.Cond{
  #    id: {scope_id, 0},
  #    escapes: [assigns],
  #    render: fn ->
  #      %{
  #        categories:
  #          for category <- assigns.categories do
  #            render = fn ->
  #              %{
  #                posts:
  #                  for post <- category.posts do
  #                    render = fn ->
  #                      proto__track_render_post__(:render, post)
  #                    end

  #                    %Phoenix.DataView.Tracked.Keyed{
  #                      id: {scope_id, 2},
  #                      key: post.id,
  #                      escapes: [post],
  #                      render: render
  #                    }
  #                  end
  #              }
  #            end

  #            %Phoenix.DataView.Tracked.Keyed{
  #              id: {scope_id, 1},
  #              key: category.id,
  #              escapes: [category],
  #              render: render
  #            }
  #          end
  #      }
  #    end
  #  }
  # end

  # def proto__track_render_post__(:make_ids, state) do
  #  scope_id = {__MODULE__, :render_post, 1}

  #  if Map.has_key?(state.visited, scope_id) do
  #    state
  #  else
  #    %{ids: ids, visited: visited, counter: counter} = state
  #    visited = Map.put(visited, scope_id, nil)
  #    ids = Map.put(ids, {scope_id, 0}, %{num: counter + 0, line: 55})
  #    state = %{state | ids: ids, visited: visited, counter: counter + 1}
  #    state
  #  end
  # end

  # def proto__track_render_post__(:render, post) do
  #  scope_id = {__MODULE__, :render_post, 1}

  #  %Phoenix.DataView.Tracked.Cond{
  #    id: {scope_id, 0},
  #    escapes: [post],
  #    render: fn ->
  #      %{
  #        title: post.title,
  #        text: post.text
  #      }
  #    end
  #  }
  # end

  test "foobar" do
    state = %{ids: %{}, visited: %{}, counter: 0}
    #%{ids: keyed_ids} = __tracked_ids_render_1__(state)
    statics = __tracked_meta__render__1__(:statics)

    assigns = %{
      categories: [
        %{
          id: 0,
          posts: [
            %{
              id: 0,
              title: "woo",
              text: "hoo"
            }
          ]
        }
      ]
    }

    tree_state = Tree.new() #keyed_ids)
    apply_state = Apply.new()

    rendered = __tracked__render__(assigns)
    {ops1, tree_state} = Tree.render(rendered, tree_state)

    IO.inspect(ops1)
    apply_state = Apply.apply(ops1, apply_state)
    IO.inspect(apply_state.rendered)

    assigns = %{
      categories: [
        %{
          id: 0,
          posts: [
            %{
              id: 0,
              title: "woo",
              text: "hoo"
            },
            %{
              id: 1,
              title: "foobar",
              text: "foo"
            }
          ]
        }
      ]
    }

    rendered = __tracked__render__(assigns)
    {ops2, tree_state} = Tree.render(rendered, tree_state)

    IO.inspect(ops2)
    apply_state = Apply.apply(ops2, apply_state)
    IO.inspect(apply_state.rendered)
  end
end
