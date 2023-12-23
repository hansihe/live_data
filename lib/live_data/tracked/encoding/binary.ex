defmodule LiveData.Tracked.Encoding.Binary do
  alias LiveData.Tracked.Tree
  alias LiveData.Tracked.Render

  #@op_render 0
  @op_put_fragment 1
  #@op_delete_fragment 2

  @expr_substitute_fragment 0
  @expr_render_template 1

  def encode(ops, state) do
    num_ops = Enum.count(ops)

    body =
      Enum.map(ops, fn op ->
        encode_op(op, state)
      end)

    [<<num_ops::integer-size(16)>>, body]
  end

  def encode_op({:s, ref, data}, state) do
    id = Render.get_alias(state.render, ref)
    body = encode_body(data, state)

    [<<@op_put_fragment, id::integer-size(32)>>, body]
  end

  def encode_body(%Tree.Ref{} = ref, state) do
    alias_num = Render.get_alias(state.render, ref)

    <<@expr_substitute_fragment, alias_num::integer-size(32)>>
  end

  def encode_body(%Tree.Template{id: template_id, slots: slots}, state) do
    num_slots = Enum.count(slots)

    encoded_slots = Enum.map(slots, &encode_body(&1, state))

    [<<@expr_render_template, template_id::integer-size(32), num_slots::integer-size(16)>>, encoded_slots]
  end

end
