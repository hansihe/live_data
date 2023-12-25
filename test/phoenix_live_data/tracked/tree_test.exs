defmodule LiveData.Tracked.FragmentTreeTest do
  use ExUnit.Case
  import LiveData.Tracked.TestHelpers

  alias LiveData.Tracked.Apply
  alias LiveData.Tracked.RenderDiff
  alias LiveData.Tracked.Encoding

  def make_module() do
    module = define_module! do
      use LiveData.Tracked

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
          content: post.text,
          postcode: post.postcode
        }
      end
    end

    module
  end

  @tag :skip
  test "temporary test" do
    module = make_module()

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

    IO.inspect module.__tracked_meta__render__1__(:statics)

    out = module.__tracked__render__(assigns)
    IO.inspect out
    IO.inspect out.render.()
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

  #  %LiveData.Tracked.Cond{
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

  #                    %LiveData.Tracked.Keyed{
  #                      id: {scope_id, 2},
  #                      key: post.id,
  #                      escapes: [post],
  #                      render: render
  #                    }
  #                  end
  #              }
  #            end

  #            %LiveData.Tracked.Keyed{
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

  #  %LiveData.Tracked.Cond{
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
    module = make_module()

    #statics = module.__tracked_meta__render__1__(:statics)

    assigns = %{
      categories: [
        %{
          id: 0,
          posts: [
            %{
              id: 0,
              title: "woo",
              text: "hoo",
              postcode: 1123
            },
            %{
              id: 1,
              title: "hello_world",
              text: "foobar",
              postcode: 5321
            },
            %{
              id: 2,
              title: "asdsadasd",
              text: "ahjsdiuhasuyidh",
              postcode: 5321
            },
            %{
              id: 3,
              title: "lsasdgvcx",
              text: "kasdtyucqapqlkdsah",
              postcode: 5321
            },
            %{
              id: 4,
              title: "klcbnbwbre",
              text: "casdsoapoads",
              postcode: 5321
            },
          ]
        },
        %{
          id: 1,
          posts: [
            %{
              id: 5,
              title: "uifsaydufih",
              text: "dsaiuyasdf",
              postcode: 5321
            },
            %{
              id: 6,
              title: "asdlkw",
              text: "kduyasd",
              postcode: 5321
            },
            %{
              id: 7,
              title: "lkajdeb",
              text: "lksdfsafg",
              postcode: 5321
            },
            %{
              id: 8,
              title: "kjankwne",
              text: "wlejakyhdi",
              postcode: 5321
            },
            %{
              id: 9,
              title: "aenwbehh",
              text: "ae;akjwoieoiu",
              postcode: 5321
            },
            %{
              id: 10,
              title: "alkwewjhbeah",
              text: "aehjerwbhg",
              postcode: 5321
            },
          ]
        }
      ]
    }

    tree_state = RenderDiff.new() #keyed_ids)
    encoder = Encoding.JSON.new()
    apply_state = Apply.new()

    rendered = module.__tracked__render__(assigns)
    {ops1, tree_state} = RenderDiff.render(rendered, tree_state)

    #IO.inspect(ops1)

    {_json_ops, _encoder} = Encoding.JSON.format(ops1, encoder)
    #IO.inspect json_ops

    apply_state = Apply.apply(ops1, apply_state)
    assert apply_state.rendered == %{
      categories: [
        %{
          posts: [
            %{content: "hoo", postcode: 1123, title: "woo"},
            %{content: "foobar", postcode: 5321, title: "hello_world"},
            %{content: "ahjsdiuhasuyidh", postcode: 5321, title: "asdsadasd"},
            %{content: "kasdtyucqapqlkdsah", postcode: 5321, title: "lsasdgvcx"},
            %{content: "casdsoapoads", postcode: 5321, title: "klcbnbwbre"}
          ]
        },
        %{
          posts: [
            %{content: "dsaiuyasdf", postcode: 5321, title: "uifsaydufih"},
            %{content: "kduyasd", postcode: 5321, title: "asdlkw"},
            %{content: "lksdfsafg", postcode: 5321, title: "lkajdeb"},
            %{content: "wlejakyhdi", postcode: 5321, title: "kjankwne"},
            %{content: "ae;akjwoieoiu", postcode: 5321, title: "aenwbehh"},
            %{content: "aehjerwbhg", postcode: 5321, title: "alkwewjhbeah"}
          ]
        }
      ]
    }

    assigns = %{
      categories: [
        %{
          id: 0,
          posts: [
            %{
              id: 0,
              title: "woo",
              text: "hoo",
              postcode: 1234
            },
            %{
              id: 1,
              title: "woo",
              text: "hoo",
              postcode: 1234
            },
            %{
              id: 2,
              title: "woo",
              text: "hoo",
              postcode: 1234
            },
            %{
              id: 3,
              title: "woo",
              text: "hoo",
              postcode: 1234
            },
            %{
              id: 4,
              title: "foobar",
              text: "foo",
              postcode: 1234
            }
          ]
        }
      ]
    }

    rendered = module.__tracked__render__(assigns)
    {ops2, _tree_state} = RenderDiff.render(rendered, tree_state)

    #IO.inspect(ops2)

    {_json_ops, _encoder} = Encoding.JSON.format(ops2, encoder)
    #IO.inspect json_ops

    apply_state = Apply.apply(ops2, apply_state)
    assert apply_state.rendered == %{
      categories: [
        %{
          posts: [
            %{content: "hoo", postcode: 1234, title: "woo"},
            %{content: "hoo", postcode: 1234, title: "woo"},
            %{content: "hoo", postcode: 1234, title: "woo"},
            %{content: "hoo", postcode: 1234, title: "woo"},
            %{content: "foo", postcode: 1234, title: "foobar"}
          ]
        }
      ]
    }
  end
end
