defmodule Mix.Brando.Igniter.OptionalDependencyTest do
  use ExUnit.Case, async: true

  test "source helpers do not require Igniter when compiling a consumer without it" do
    script = """
    false = Code.ensure_loaded?(Igniter)
    Enum.each(System.argv(), fn file ->
      [{module, _beam}] = Code.compile_file(file)
      false = module.__mix_recompile__?()
      false = function_exported?(module, :plan, 1)
    end)
    IO.puts("optional helpers compile without Igniter")
    """

    files = Path.wildcard("lib/mix/brando/igniter/**/*.ex")
    {output, status} = System.cmd(System.find_executable("elixir"), ["-e", script, "--" | files], stderr_to_stdout: true)

    assert status == 0, output
    assert output == "optional helpers compile without Igniter\n"
  end

  test "Mix recompiles optional helpers when Igniter is added or removed" do
    root = Path.join(System.tmp_dir!(), "brando-optional-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "optional"))

    File.write!(Path.join(root, "mix.exs"), """
    defmodule OptionalConsumer.MixProject do
      use Mix.Project
      def project, do: [app: :optional_consumer, version: "0.1.0", prune_code_paths: false]
    end
    """)

    File.cp!("lib/mix/brando/igniter/input.ex", Path.join(root, "lib/input.ex"))
    options = [cd: root, env: [{"MIX_ENV", "dev"}], stderr_to_stdout: true]
    elixir = System.find_executable("elixir")

    stub =
      "[{_, beam}] = Code.compile_string(\"defmodule Igniter do end\"); File.write!(\"optional/Elixir.Igniter.beam\", beam)"

    assert {_, 0} = System.cmd(elixir, ["-e", stub], options)

    absent =
      "false = Mix.Brando.Igniter.Input.__mix_recompile__?(); false = function_exported?(Mix.Brando.Igniter.Input, :identifier, 2)"

    present = ~s|{:ok, "slug"} = Mix.Brando.Igniter.Input.identifier("slug", "field")|

    for {paths, check} <- [{[], absent}, {["-pa", "optional"], present}, {[], absent}] do
      {output, status} = System.cmd(elixir, paths ++ ["-S", "mix", "run", "--no-start", "-e", check], options)
      assert status == 0, output
    end
  end
end
