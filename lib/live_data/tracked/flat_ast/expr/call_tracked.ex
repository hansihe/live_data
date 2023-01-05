alias LiveData.Tracked.FlatAst.Expr

defmodule Expr.CallTracked do
  defstruct inner: nil

  def new(%Expr.CallMF{} = inner) do
    %__MODULE__{
      inner: inner
    }
  end
end

defimpl Expr, for: Expr.CallTracked do

  def transform(%Expr.CallTracked{} = expr, acc, fun) do
    # Behaves as if CallMF in normal circumstances
    {inner, acc} = Expr.transform(expr.inner, acc, fun)
    {%{expr | inner: inner}, acc}
  end

end
