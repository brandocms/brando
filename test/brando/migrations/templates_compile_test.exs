defmodule Brando.Migrations.TemplatesCompileTest do
  # `mix brando.gen.migrations` copies these templates into every site's
  # `priv/repo/migrations`, where each warning prints on every compile.
  use ExUnit.Case, async: false

  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")

  test "every upgrade migration template compiles without warnings" do
    warnings =
      @templates
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(&compile_warnings/1)

    assert warnings == []
  end

  defp compile_warnings(path) do
    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        for {module, _bytecode} <- Code.compile_file(path) do
          :code.purge(module)
          :code.delete(module)
        end
      end)

    for %{severity: :warning, message: message} = diagnostic <- diagnostics,
        not String.starts_with?(message, "redefining module"),
        do: "#{Path.basename(path)}:#{inspect(diagnostic.position)}: #{message}"
  end
end
