defmodule Brando.Migrations.TemplatesCompileTest do
  # `mix brando.gen.migrations` copies these templates into every site's
  # `priv/repo/migrations`, where each warning prints on every compile.
  #
  # They compile in an `elixir` of their own: loading and then purging some
  # 230 modules full of SQL literals in the test VM holds up the code server
  # for every other test running beside this one.
  use ExUnit.Case, async: true

  @moduletag timeout: :timer.minutes(3)

  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")

  @script ~S"""
  [templates] = System.argv()

  templates
  |> Path.join("*.exs")
  |> Path.wildcard()
  |> Enum.sort()
  |> Enum.each(fn path ->
    {_result, diagnostics} = Code.with_diagnostics(fn -> Code.compile_file(path) end)

    for %{severity: :warning, message: message} = diagnostic <- diagnostics,
        not String.starts_with?(message, "redefining module") do
      IO.puts("WARNING #{Path.basename(path)}:#{inspect(diagnostic.position)}: #{message}")
    end
  end)
  """

  test "every upgrade migration template compiles without warnings" do
    paths = Enum.flat_map(:code.get_path(), &["-pa", to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", @script, @templates], stderr_to_stdout: true)

    assert status == 0, output
    assert output |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "WARNING ")) == []
  end
end
