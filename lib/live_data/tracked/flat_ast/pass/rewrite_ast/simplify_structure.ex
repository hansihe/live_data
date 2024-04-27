defmodule LiveData.Tracked.FlatAst.Pass.RewriteAst.SimplifyStructure do
alias LiveData.Tracked.FragmentTree

  def simplify_structure(static_structure) do
    simplify_structure_rec(nil, static_structure)
  end

  # ==== Error cases ====

  defp simplify_structure_rec(:make_map_key, {:literal, literal} = lit) when is_atom(literal) or is_binary(literal) or is_number(literal) do
    # Binaries or Atoms or Numbers as map keys are OK
    simplify_structure(lit)
  end

  defp simplify_structure_rec(:make_map_key, {:make_binary, _elems} = node) do
    # Binaries as map keys are OK
    simplify_structure(node)
  end

  defp simplify_structure_rec(:make_map_key, %FragmentTree.Slot{} = slot) do
    # Slots as map keys are OK
    slot
  end

  defp simplify_structure_rec(:make_map_key, _other) do
    # Other map keys throw errors.
    throw %CompileError{
      description: "Non atom, binaries or numbers are not allowed in map keys"
    }
  end

  # ==== Recursive walk and simplification ====
  defp simplify_structure_rec(_parent, {:make_binary, elements}) do
    simplify_elems = Enum.map(elements, fn elem -> simplify_structure_rec(:make_binary, elem) end)
    {:make_binary, simplify_elems}
  end

  defp simplify_structure_rec(:make_binary, {:to_string, sub}) do
    # SIMPLIFICATION: :to_string in :make_binary disappears.
    simplify_structure_rec(:to_string, sub)
  end

  defp simplify_structure_rec(_parent, {:to_string, sub}) do
    {:to_string, simplify_structure_rec(:to_string, sub)}
  end

  defp simplify_structure_rec(_parent, {:make_map, prev_map, kvs}) do
    prev_map = if prev_map != nil, do: simplify_structure_rec(prev_map, :make_map_prev)
    kvs = Enum.map(kvs, fn {key, value} ->
      key = simplify_structure_rec(:make_map_key, key)
      value = simplify_structure_rec(:make_map_value, value)
      {key, value}
    end)
    {:make_map, prev_map, kvs}
  end

  defp simplify_structure_rec(_parent, {:literal, _literal} = literal) do
    literal
  end

  defp simplify_structure_rec(_parent, {:make_tuple, elements}) do
    elements = Enum.map(elements, &simplify_structure_rec(:make_tuple, &1))
    {:make_tuple, elements}
  end

  defp simplify_structure_rec(_parent, [head | tail]) when is_list(tail) do
    [
      simplify_structure_rec(:make_list, head)
      | simplify_structure_rec(:make_list, tail)
    ]
  end

  defp simplify_structure_rec(_parent, [head | tail]) do
    [
      simplify_structure_rec(:make_list, head)
      | simplify_structure_rec(:make_cons_tail, tail)
    ]
  end

  defp simplify_structure_rec(_parent, %FragmentTree.Slot{} = slot) do
    slot
  end

end
