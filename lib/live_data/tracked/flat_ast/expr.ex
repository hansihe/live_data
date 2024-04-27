defprotocol LiveData.Tracked.FlatAst.Expr do
  @type t :: t()

  @type entry_kind :: :value | :bind | :bind_ref | :literal | :scope | :pattern
  @type entry_identifier :: any()
  @type expr_ref :: any()
  @type acc :: any()

  @type location :: any()

  @type visitor :: (entry_kind(), entry_identifier(), expr_ref(), acc() -> {expr_ref(), acc()})

  @doc """
  Universal transformation function for an expression.

  The visitor function is called for the following inner entities:
   * `:value` - The expression evaluates a subexpression in the scope
     and uses the return value.
   * `:bind` - The expression binds a new value in the current scope.
   * `:bind_ref` - The expression references a bind from the scope.
   * `:literal` - The expression uses a literal value.
   * `:scope` - The expression evaluates an inner scope and uses the
     return value. Any assignments within the scope will not be present
     in the current scope.
   * `:pattern` - The expression matches on a pattern.
  """
  @spec transform(t(), acc(), visitor()) :: {t(), acc()}
  def transform(expr, acc, fun)

  @spec location(t()) :: location()
  def location(expr)

end
