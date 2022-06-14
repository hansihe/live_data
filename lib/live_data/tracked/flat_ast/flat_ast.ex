defmodule LiveData.Tracked.FlatAst do
  @moduledoc false

  defstruct exprs: %{},
            patterns: %{},
            variables: %{},
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

  def set_location(ast, item_id, line, column \\ nil) do
    put_in(ast.locations[item_id], {line, column})
  end

  def add_expr(ast, body \\ nil) do
    {id, ast} = make_expr_id(ast)
    ast = %{ast | exprs: Map.put(ast.exprs, id, body)}
    {id, ast}
  end

  def set_expr(ast, expr_id, body) do
    %{ast | exprs: Map.put(ast.exprs, expr_id, body)}
  end

  def add_pattern(ast, pattern) do
    {id, ast} = make_pattern_id(ast)
    ast = %{ast | patterns: Map.put(ast.patterns, id, pattern)}
    {id, ast}
  end

  def add_variable(ast, variable, expr_id) do
    %{ast | variables: Map.put(ast.variables, expr_id, variable)}
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

  def get(ast, {:expr, _eid} = id) do
    Map.fetch!(ast.exprs, id)
  end

  def get(ast, {:pattern, _pid} = id) do
    Map.fetch!(ast.patterns, id)
  end

  def get(ast, {:literal, _lid} = id) do
    {:literal, Map.fetch!(ast.literals, id)}
  end

  def get(_ast, {:expr_bind, _eid, _selector} = id) do
    id
  end
end
