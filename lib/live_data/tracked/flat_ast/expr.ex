defprotocol LiveData.Tracked.FlatAst.Expr do

  @type t :: t()

  @type entry_kind :: :value | :ref | :literal | :scope | :pattern
  @type entry_identifier :: any()
  @type expr_ref :: any()
  @type acc :: any()

  @type visitor :: (entry_kind(), entry_identifier(), expr_ref(), acc() -> {expr_ref(), acc()})

  @doc """
  Universal transformation function for an expression.

  """
  @spec transform(t(), acc(), visitor()) :: {t(), acc()}
  def transform(expr, acc, fun)

end
