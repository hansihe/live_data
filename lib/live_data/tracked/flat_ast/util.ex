defmodule LiveData.Tracked.FlatAst.Util do
  @moduledoc false

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr

  def unique_integer do
    :erlang.unique_integer()
  end

  @doc """
  Given an arbitrarily nested list data structure, will flatten it into a single
  list.
  """
  def recursive_flatten(val) do
    res = recursive_flatten_rec(val, [])
    Enum.reverse(res)
  end

  defp recursive_flatten_rec([], acc) do
    acc
  end

  defp recursive_flatten_rec([head | tail], acc) do
    acc = recursive_flatten_rec(head, acc)
    recursive_flatten_rec(tail, acc)
  end

  defp recursive_flatten_rec(value, acc) do
    [value | acc]
  end

  @doc """
  Traverses the AST starting at `id`.

  User provided function will be called on a node before its children.
  """
  def traverse(ast, id, expr \\ nil, acc, fun)

  def traverse(ast, id, nil, acc, fun) do
    expr = FlatAst.get(ast, id)
    traverse(ast, id, expr, acc, fun)
  end

  def traverse(ast, id, expr, acc, fun) do
    case fun.(id, expr, acc) do
      {:handled, acc} ->
        acc

      {:continue, acc} ->
        children = child_exprs(expr)
        Enum.reduce(children, acc, fn child, acc -> traverse(ast, child, acc, fun) end)
    end
  end

  @doc """
  Traverses the AST starting at `id`.

  User provided function will be called on a node after its children.
  """
  def traverse_post(ast, id, expr \\ nil, acc, fun)

  def traverse_post(ast, id, nil, acc, fun) do
    expr = FlatAst.get(ast, id)
    traverse(ast, id, expr, acc, fun)
  end

  def traverse_post(ast, id, expr, acc, fun) do
    children = child_exprs(expr)
    Enum.reduce(children, acc, fn child, acc -> traverse_post(ast, child, acc, fun) end)

    fun.(id, expr, acc)
  end

  @doc """
  Expression traversal/update primitive.

  Given an expression, an accululator and a function, will apply the function
  over all subexpressions of the expression.

  The accumulator will be woven through, and will be returned alongside the
  updated expression.
  """
  def transform_expr(expr, acc, fun)

  def transform_expr(%Expr.AccessField{} = expr, acc, fun) do
    {new_top, acc} = fun.(:value, :top, expr.top, acc)
    new_expr = %{expr | top: new_top}
    {new_expr, acc}
  end

  def transform_expr(%Expr.Block{exprs: exprs} = expr, acc, fun) do
    num_items = Enum.count(exprs)

    {new_exprs, acc} =
      exprs
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {expr, idx}, acc ->
        fun.(:value, {idx, idx == num_items - 1}, expr, acc)
      end)

    new_expr = %{expr | exprs: new_exprs}
    {new_expr, acc}
  end

  def transform_expr(%Expr.Scope{exprs: exprs} = expr, acc, fun) do
    num_items = Enum.count(exprs)

    {new_exprs, acc} =
      exprs
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {expr, idx}, acc ->
        fun.(:value, {idx, idx == num_items - 1}, expr, acc)
      end)

    new_expr = %{expr | exprs: new_exprs}
    {new_expr, acc}
  end

  def transform_expr(%Expr.CallMF{} = expr, acc, fun) do
    {new_module, acc} =
      if expr.module do
        fun.(:value, :mod, expr.module, acc)
      else
        {nil, acc}
      end

    {new_function, acc} = fun.(:value, :fun, expr.function, acc)

    {new_args, acc} =
      expr.args
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {arg, idx}, acc ->
        fun.(:value, {:arg, idx}, arg, acc)
      end)

    new_expr = %{
      expr |
      module: new_module,
      function: new_function,
      args: new_args
    }

    {new_expr, acc}
  end

  def transform_expr(%Expr.Case{} = expr, acc, fun) do
    {new_value, acc} = fun.(:value, :value, expr.value, acc)

    {clauses, acc} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn
        {%Expr.Case.Clause{} = clause, idx}, acc ->
          {{new_pattern, new_binds}, acc} = fun.(:pattern, {idx, :pattern}, {clause.pattern, clause.binds}, acc)

          {new_guard, acc} =
            if clause.guard do
              fun.(:scope, {idx, :guard}, clause.guard, acc)
            else
              {nil, acc}
            end

          {new_body, acc} = fun.(:scope, {idx, :body}, clause.body, acc)

          {%{clause | pattern: new_pattern, binds: new_binds, guard: new_guard, body: new_body}, acc}
      end)

    new_expr = %{expr | value: new_value, clauses: clauses}
    {new_expr, acc}
  end

  def transform_expr(%Expr.Fn{} = expr, acc, fun) do
    {clauses, acc} =
      expr.clauses
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn
        {%Expr.Fn.Clause{} = clause, idx}, acc ->
          {{new_patterns, new_binds}, acc} = fun.(:pattern, {idx, :pattern}, {clause.patterns, clause.binds}, acc)

          {new_guard, acc} =
            if clause.guard do
              fun.(:scope, {idx, :guard}, clause.guard, acc)
            else
              {nil, acc}
            end

          {new_body, acc} = fun.(:scope, {idx, :body}, clause.body, acc)

          {%{clause | patterns: new_patterns, binds: new_binds, guard: new_guard, body: new_body}, acc}
      end)

    new_expr = %{expr | clauses: clauses}
    {new_expr, acc}
  end

  def transform_expr(%Expr.For{} = expr, acc, fun) do
    {new_items, acc} =
      expr.items
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn
        {{:loop, pattern, binds, body}, idx}, acc ->
          {{new_pattern, new_binds}, acc} = fun.(:pattern, {idx, :pattern}, {pattern, binds}, acc)
          {new_body, acc} = fun.(:scope, {idx, :generator}, body, acc)
          {{:loop, new_pattern, new_binds, new_body}, acc}

        {{:filter, body}, idx}, acc ->
          {new_body, acc} = fun.(:scope, {idx, :filter}, body, acc)
          {{:filter, new_body}, acc}
      end)

    {new_into, acc} =
      if expr.into do
        fun.(:value, :into, expr.into, acc)
      else
        {nil, acc}
      end

    {new_inner, acc} = fun.(:scope, :inner, expr.inner, acc)

    new_expr = %{
      expr |
      items: new_items,
      into: new_into,
      inner: new_inner
    }
    {new_expr, acc}
  end

  def transform_expr(%Expr.MakeMap{} = expr, acc, fun) do
    {new_struct, acc} = if expr.struct do
      fun.(:value, :struct, expr.struct, acc)
    else
      {nil, acc}
    end

    {new_prev, acc} = if expr.prev do
      fun.(:value, :prev, expr.prev, acc)
    else
      {nil, acc}
    end

    {new_kvs, acc} =
      expr.kvs
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {{key, val}, idx}, acc ->
        {new_key, acc} = fun.(:value, {idx, :key}, key, acc)
        {new_val, acc} = fun.(:value, {idx, :val}, val, acc)
        {{new_key, new_val}, acc}
      end)

    new_expr = %{
      expr |
      struct: new_struct,
      prev: new_prev,
      kvs: new_kvs
    }
    {new_expr, acc}
  end

  def transform_expr(%Expr.MakeTuple{} = expr, acc, fun) do
    {new_elems, acc} =
      expr.elements
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {elem, idx}, acc ->
        fun.(:value, idx, elem, acc)
      end)

    new_expr = %{ expr | elements: new_elems }
    {new_expr, acc}
  end

  def transform_expr(%Expr.Match{} = expr, acc, fun) do
    {{new_pattern, new_binds}, acc} = fun.(:pattern, :lhs, {expr.pattern, expr.binds}, acc)
    {new_rhs, acc} = fun.(:value, :rhs, expr.rhs, acc)

    new_expr = %{expr | pattern: new_pattern, binds: new_binds, rhs: new_rhs}
    {new_expr, acc}
  end

  def transform_expr(%Expr.MakeCons{} = expr, acc, fun) do
    {new_head, acc} = fun.(:value, :head, expr.head, acc)
    {new_tail, acc} = fun.(:value, :tail, expr.tail, acc)

    new_expr = %{expr | head: new_head, tail: new_tail}
    {new_expr, acc}
  end

  def transform_expr(%Expr.MakeBinary{} = expr, acc, fun) do
    # TODO size specifier
    {new_components, acc} =
      expr.components
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {{elem, specifiers}, idx}, acc ->
        {new_elem, acc} = fun.(:value, idx, elem, acc)
        {{new_elem, specifiers}, acc}
      end)
    new_expr = %{expr | components: new_components}
    {new_expr, acc}
  end

  def transform_expr(%Expr.MakeStatic{} = expr, acc, fun) do
    {new_slots, acc} =
      expr.slots
      |> Enum.with_index()
      |> Enum.map_reduce(acc, fn {elem, idx}, acc ->
        fun.(:value, idx, elem, acc)
      end)
    new_expr = %{expr | slots: new_slots}
    {new_expr, acc}
  end

  def transform_expr(%Expr.Var{} = expr, acc, fun) do
    {new_ref_expr, acc} =
      case expr.ref_expr do
        {:expr_bind, _eid, _selector} = ref_expr ->
          fun.(:ref, :ref, ref_expr, acc)
      end

    new_expr = %{expr | ref_expr: new_ref_expr}
    {new_expr, acc}
  end

  def transform_expr({:expr_bind, _eid, _selector} = ref_expr, acc, fun) do
    fun.(:ref, :ref, ref_expr, acc)
  end

  def transform_expr({:literal, _lid} = literal_id, acc, fun) do
    fun.(:literal, :literal, literal_id, acc)
  end

  def reduce_expr(expr, acc, fun) do
    {_new_expr, acc} =
      transform_expr(expr, acc, fn
        kind, selector, value, acc ->
          acc = fun.(kind, selector, value, acc)
          {value, acc}
      end)

    acc
  end

  @doc """
  Given an expression, will return a list of all subexpressions.
  """
  def child_exprs(expr) do
    reduce_expr(expr, [], fn
      :value, _selector, child_expr_id, acc ->
        [child_expr_id | acc]
      :scope, _selector, child_expr_id, acc ->
        [child_expr_id | acc]
      _, _, _, acc ->
        acc
    end)
    |> Enum.reverse()
  end
end
