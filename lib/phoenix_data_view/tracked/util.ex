defmodule Phoenix.DataView.Tracked.Util do
  def decompose_call!(_kind, {{:unquote, _, [name]}, _, args}, _env) do
    {name, args}
  end

  def decompose_call!(kind, call, env) do
    case Macro.decompose_call(call) do
      {name, args} ->
        {name, args}

      :error ->
        compile_error!(
          env,
          "first argument of #{kind}n must be a call, got: #{Macro.to_string(call)}"
        )
    end
  end

  def compile_error!(env, description) do
    raise CompileError, line: env.line, file: env.file, description: description
  end
end
