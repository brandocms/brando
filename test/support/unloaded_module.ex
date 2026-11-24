defmodule Brando.Test.UnloadedModule do
  @moduledoc """
  Compiles `quoted` to `.beam` files in `dir`, unloads the modules and puts
  `dir` on the code path: the state a Mix task, a release `eval` or a fresh
  node meets a schema in, where `function_exported?/3` says `false` until
  something loads the module.

  Call it from a `@tag :tmp_dir` test; the code path entry goes when the
  test exits.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  def compile(quoted, dir) do
    for {module, beam} <- Code.compile_quoted(quoted) do
      File.write!(Path.join(dir, "#{module}.beam"), beam)
      :code.delete(module)
      :code.purge(module)
    end

    Code.prepend_path(dir)
    on_exit(fn -> Code.delete_path(dir) end)
    :ok
  end
end
