defmodule LiveData.Tracked.FlatAst do
  @moduledoc """
  Base implementation of the FlatAst.

  FlatAst is a different representation of an Elixir AST where every node
  has an ID, and all nodes are stored in a flat map. This is in contrast to
  the regular Elixir AST, where nodes have no ID and are represented as an
  explicit tree with nesting.

  Contains utilities for converting from and to the regular Elixir AST.
  """

  defstruct exprs: %{},
            patterns: %{},
            binds: %{},
            binds_back: %{},
            binds_by_expr_id: %{},
            literals: %{},
            literals_back: %{},
            locations: %{},
            root: nil,
            next_id: 0,
            aux: nil

  def new() do
    %__MODULE__{}
  end

  def with_aux(ast, aux, inner) do
    old_aux = ast.aux
    ast = %{ast | aux: aux}
    {value, ast} = inner.(ast)
    ast = %{ast | aux: old_aux}
    {value, ast}
  end

  def set_root(ast, expr_id) do
    %{
      ast
      | root: expr_id
    }
  end

  def next_id(ast) do
    next_id = ast.next_id
    ast = %{ast | next_id: next_id + 1}
    {next_id, ast}
  end

  def make_expr_id(ast) do
    {id, ast} = next_id(ast)
    {{:expr, id}, ast}
  end

  def make_pattern_id(ast) do
    {id, ast} = next_id(ast)
    {{:pattern, id}, ast}
  end

  def make_literal_id(ast) do
    {id, ast} = next_id(ast)
    {{:literal, id}, ast}
  end

  def make_bind_id(ast) do
    {id, ast} = next_id(ast)
    {{:bind, id}, ast}
  end

  def set_location(ast, item_id, line, column \\ nil) do
    put_in(ast.locations[item_id], {line, column})
  end

  def add_expr(ast, body \\ nil) do
    {id, ast} = make_expr_id(ast)
    ast = %{ast | exprs: Map.put(ast.exprs, id, body)}
    {id, ast}
  end

  @doc """
  Only safe to call if you know the given expr has no usages.
  """
  def rm_expr(ast, expr_id) do
    %{ast | exprs: Map.delete(ast.exprs, expr_id)}
  end

  def set_expr(ast, expr_id, body) do
    %{ast | exprs: Map.put(ast.exprs, expr_id, body)}
  end

  def add_pattern(ast, pattern) do
    {id, ast} = make_pattern_id(ast)
    ast = %{ast | patterns: Map.put(ast.patterns, id, pattern)}
    {id, ast}
  end

  def gen_variable(ast, name \\ :gen) do

  end

  @doc """
  Adds a bint which targets `to` with selector `selector`.
  """
  def add_bind(ast, {:expr, _eid} = to, selector, variable) do
    data = %{
      expr: to,
      selector: selector,
      variable: variable,
    }

    case Map.fetch(ast.binds_back, data) do
      {:ok, id} ->
        {id, ast}

      :error ->
        {id, ast} = make_bind_id(ast)
        ast = %{ast |
          binds: Map.put(ast.binds, id, data),
          binds_back: Map.put(ast.binds_back, data, id),
          binds_by_expr_id: Map.update(ast.binds_by_expr_id, to, [id], &[id | &1]),
        }
        {id, ast}
    end
  end

  def get_literal_id_by_value(ast, value) do
    Map.fetch(ast.literals_back, value)
  end

  def add_literal(ast, literal) do
    case Map.fetch(ast.literals_back, literal) do
      {:ok, literal_id} ->
        {literal_id, ast}

      :error ->
        {id, ast} = make_literal_id(ast)

        ast = %{
          ast
          | literals: Map.put(ast.literals, id, literal),
            literals_back: Map.put(ast.literals_back, literal, id)
        }

        {id, ast}
    end
  end

  def get_bind_data(ast, {:bind, _bid} = id) do
    Map.fetch!(ast.binds, id)
  end

  def get(ast, {:expr, _eid} = id) do
    Map.fetch!(ast.exprs, id)
  end

  def get(ast, {:pattern, _pid} = id) do
    Map.fetch!(ast.patterns, id)
  end

  def get(ast, {:literal, _lid} = id) do
    {:literal_value, Map.fetch!(ast.literals, id)}
  end

  def get(_ast, {:bind, _bid} = id) do
    id
  end
end
