defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst.MakeStructure do
  @moduledoc """
  First pass of rewriting.

  This will traverse the function from the return position, constructing the
  static fragment with slots. Each static fragment is keyed by the expr it will
  take the place of in the rewritten AST.

  Traversed expressions are also registered for use by the later passes.
  """

  alias LiveData.Tracked.FlatAst
  alias LiveData.Tracked.FlatAst.Expr
  alias LiveData.Tracked.FlatAst.Pass.RewriteAst.StaticsAgent
  alias LiveData.Tracked.Tree.Slot

  def rewrite_make_structure(expr_id, ast, state) do
    if StaticsAgent.fetch(state, expr_id) != :error do
      expr_id
    else
      :ok = StaticsAgent.add(state, expr_id)
      static_structure = rewrite_make_structure_rec(expr_id, ast, expr_id, state)

      {:ok, static_result} = StaticsAgent.fetch(state, expr_id)

      case {static_structure, static_result} do
        {%Slot{num: 0}, %{state: :unfinished, slots: [slot_zero_expr], key: nil}} ->
          case StaticsAgent.fetch(state, slot_zero_expr) do
            {:ok, %{state: :finished} = val} ->
              :ok = StaticsAgent.set(state, expr_id, val)

            _ ->
              slot_zero_expr
          end

        _ ->
          :ok = StaticsAgent.finalize(state, expr_id, static_structure)
          expr_id
      end
    end
  end

  def rewrite_make_structure_rec(expr_id, ast, static_id, state) do
    expr = FlatAst.get(ast, expr_id)
    rewrite_make_structure_rec(expr, expr_id, ast, static_id, state)
  end

  def rewrite_make_structure_rec(%Expr.Scope{exprs: exprs}, _expr_id, ast, static_id, state) do
    result_expr = List.last(exprs)
    rewrite_make_structure_rec(result_expr, ast, static_id, state)
  end

  def rewrite_make_structure_rec(%Expr.Case{} = expr, expr_id, ast, static_id, state) do
    :ok = StaticsAgent.add_dependencies(state, ast, [expr.value])

    for clause <- expr.clauses do
      _inner_expr = rewrite_make_structure(clause.body, ast, state)
    end
    :ok = StaticsAgent.add_traversed(state, expr_id)

    StaticsAgent.add_slot(state, static_id, expr_id)
  end

  def rewrite_make_structure_rec(%Expr.For{} = expr, expr_id, ast, static_id, state) do
    items =
      Enum.map(expr.items, fn
        {:loop, _pattern, _binds, expr} -> expr
        {:filter, expr} -> expr
      end)

    :ok = StaticsAgent.add_dependencies(state, ast, [expr.into | items])

    _inner_expr = rewrite_make_structure(expr.inner, ast, state)
    :ok = StaticsAgent.add_traversed(state, expr_id)

    StaticsAgent.add_slot(state, static_id, expr_id)
  end

  def rewrite_make_structure_rec(%Expr.CallTracked{}, expr_id, ast, static_id, state) do
    :ok = StaticsAgent.add_dependencies(state, ast, [expr_id])
    StaticsAgent.add_slot(state, static_id, expr_id)
  end

  def rewrite_make_structure_rec(%Expr.CallMF{module: nil}, expr_id, ast, static_id, state) do
    :ok = StaticsAgent.add_dependencies(state, ast, [expr_id])
    StaticsAgent.add_slot(state, static_id, expr_id)
  end

  def rewrite_make_structure_rec(%Expr.CallMF{} = expr, expr_id, ast, static_id, state) do
    case {FlatAst.get(ast, expr.module), FlatAst.get(ast, expr.function)} do
      {{:literal_value, LiveData.Tracked.Dummy}, {:literal_value, :keyed_stub}} ->
        [key_expr, value_expr] = expr.args

        :ok = StaticsAgent.add_dependencies(state, ast, [key_expr])
        :ok = StaticsAgent.set_key(state, static_id, key_expr)

        rewrite_make_structure_rec(value_expr, ast, static_id, state)

      {{:literal_value, LiveData.Tracked.Dummy}, {:literal_value, :track_stub}} ->
        # This case should have been rewritten to `Expr.CallTracked` in a previous pass.
        raise "unreachable"

      {{:literal_value, LiveData.Tracked.Dummy}, {:literal_value, :custom_fragment_stub}} ->
        [_custom_fragment_id] = expr.args
        # TODO: Reference the custom fragment
        throw "todo"

      {{:literal_value, LiveData.Tracked.Dummy}, {:literal_value, :hook_stub}} ->
        [_hook_module, _subtrees] = expr.args
        # TODO: Reference the hook
        throw "todo"

      _ ->
        :ok = StaticsAgent.add_dependencies(state, ast, [expr_id])
        StaticsAgent.add_slot(state, static_id, expr_id)
    end
  end

  def rewrite_make_structure_rec(%Expr.MakeMap{struct: nil, prev: nil} = expr, _expr_id, ast, static_id, state) do
    kvs_static =
      Enum.map(expr.kvs, fn {key, val} ->
        key_rewrite = rewrite_make_structure_rec(key, ast, static_id, state)
        val_rewrite = rewrite_make_structure_rec(val, ast, static_id, state)

        {key_rewrite, val_rewrite}
      end)

    {:make_map, nil, kvs_static}
  end

  def rewrite_make_structure_rec(%Expr.MakeTuple{elements: elems}, _expr_id, ast, static_id, state) do
    elems_static = Enum.map(elems, &rewrite_make_structure_rec(
          &1, ast, static_id, state))

    {:make_tuple, elems_static}
  end

  def rewrite_make_structure_rec({:literal_value, lit}, _expr_id, _ast, _static_id, _state) do
    {:literal, lit}
  end

  def rewrite_make_structure_rec(%Expr.MakeCons{} = expr, _expr_id, ast, static_id, state) do
    head_rewrite = rewrite_make_structure_rec(expr.head, ast, static_id, state)
    tail_rewrite = rewrite_make_structure_rec(expr.tail, ast, static_id, state)

    [head_rewrite | tail_rewrite]
  end

  def rewrite_make_structure_rec(%Expr.MakeBinary{} = expr, expr_id, ast, static_id, state) do
    if Enum.all?(expr.components, fn
      {_expr, {:binary, _, _}} -> true
      _ -> false
    end) do
      # Only :binary specifiers! We can discard them and convert into a :make_binary
      # template operation which simply performs concatenation.
      elems_static = Enum.map(expr.components, fn {expr, _specifier} ->
        rewrite_make_structure_rec(expr, ast, static_id, state)
      end)
      {:make_binary, elems_static}
    else
      # If we have non-:binary specifiers, we fall back to binary in slot.
      :ok = StaticsAgent.add_dependencies(state, ast, [expr_id])
      StaticsAgent.add_slot(state, static_id, expr_id)
    end
  end

  def rewrite_make_structure_rec(_expr, expr_id, ast, static_id, state) do
    :ok = StaticsAgent.add_dependencies(state, ast, [expr_id])
    StaticsAgent.add_slot(state, static_id, expr_id)
  end
end
