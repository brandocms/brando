defmodule Mix.Brando.Igniter.OptionalDependencyTest do
  use ExUnit.Case, async: true

  test "source helpers do not require Igniter when compiling a consumer without it" do
    script = """
    false = Code.ensure_loaded?(Igniter)
    Enum.each(System.argv(), fn file -> [] = Code.compile_file(file) end)
    IO.puts("optional helpers compile without Igniter")
    """

    files = Path.wildcard("lib/mix/brando/igniter/**/*.ex")
    {output, status} = System.cmd(System.find_executable("elixir"), ["-e", script, "--" | files], stderr_to_stdout: true)

    assert status == 0, output
    assert output == "optional helpers compile without Igniter\n"
  end
end
