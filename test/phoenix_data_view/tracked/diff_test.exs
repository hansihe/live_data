defmodule Phoenix.DataView.Tracked.DiffTest do
  use ExUnit.Case

  alias Phoenix.DataView.Tracked.Diff
  alias Phoenix.DataView.Tracked.Apply

  use Phoenix.DataView.Tracked

  deft render5(assigns) do
    %{
      categories:
        for category <- assigns.categories do
          keyed category.id do
            %{
              posts:
                for post <- category.posts do
                  keyed(post.id, track(render5_post(post)))
                end
            }
          end
        end
    }
  end

  deft render5_post(post) do
    %{
      title: post.title,
      text: post.text
    }
  end

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
    %{ids: keyed_ids} = __tracked_ids_render5_1__(state)

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

    apply_state = Apply.new()

    rendered = __tracked_render5__(assigns)
    {ops1, state} = Diff.render_initial(rendered, keyed_ids)

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

    rendered = __tracked_render5__(assigns)
    {ops2, state} = Diff.render_diff(rendered, state)

    IO.inspect(ops2)
    apply_state = Apply.apply(ops2, apply_state)
    IO.inspect(apply_state.rendered)
  end
end
