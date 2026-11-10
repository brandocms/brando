defmodule Brando.AI.OptionalDependencyTest do
  use ExUnit.Case, async: true

  # Every file that names ReqLLM or LLMDB. Code calling into them compiles
  # without the optional dependency, and is unreachable then.
  @files ~w(
    lib/brando/ai.ex
    lib/brando/ai/agent/budget.ex
    lib/brando/ai/agent/loop.ex
    lib/brando/ai/cassette.ex
    lib/brando/ai/cassette/request.ex
    lib/brando/ai/cassette/response.ex
    lib/brando/images/alt_text.ex
  )

  test "the files that call ReqLLM name every one of its modules they use" do
    named =
      for file <- Path.wildcard("lib/**/*.{ex,exs}"),
          File.read!(file) =~ ~r/\b(ReqLLM|LLMDB)\./,
          do: file

    assert Enum.sort(named) == Enum.sort(@files)
  end

  test "Brando's AI modules compile without req_llm, warning-free, with AI unavailable" do
    # The test build's code paths, less req_llm and its model catalogue.
    paths =
      for path <- :code.get_path(),
          path = to_string(path),
          not String.contains?(path, ["/req_llm/", "/llm_db/"]),
          do: path

    script = """
    Code.prepend_paths(String.split(System.fetch_env!("BRANDO_PATHS"), "\\n"))
    false = Code.ensure_loaded?(ReqLLM)
    false = Code.ensure_loaded?(LLMDB)

    # The test build has these modules; the copies compiled here replace them.
    Code.compiler_options(ignore_module_conflict: true)

    # The compiler prints any warning; the match fails on it.
    {:ok, _modules, %{compile_warnings: [], runtime_warnings: []}} =
      Kernel.ParallelCompiler.compile(System.argv(), return_diagnostics: true)

    false = Brando.AI.available?()
    false = Brando.AI.enabled?()
    false = Brando.AI.configured?(model: "openai:gpt-4o", api_key: "a-key")
    {:error, :disabled} = Brando.AI.generate_text("Describe the lighthouse", model: "openai:gpt-4o", api_key: "a-key")
    {:ok, %{input_price: nil}} = Brando.AI.model_info(model: "openai:gpt-4o")

    # The same module as with req_llm, so adding it needs no recompiling.
    true = function_exported?(Brando.AI.Cassette.Response, :load, 5)
    false = Brando.AI.Cassette.active?()

    # A map that is not a ReqLLM.Context is estimated by its size.
    true = is_integer(Brando.AI.Agent.Budget.estimate(%{messages: []}))
    IO.puts("compiled without req_llm")
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["-e", script, "--" | @files],
        env: [{"BRANDO_PATHS", Enum.join(paths, "\n")}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output == "compiled without req_llm\n"
  end
end
