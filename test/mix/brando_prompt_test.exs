defmodule Mix.BrandoPromptTest do
  # Swaps the global `Mix.shell()`, so it cannot share the async phase with
  # anything that reads it.
  use ExUnit.Case, async: false

  defmodule EofShell do
    @moduledoc false
    def prompt(_message), do: :eof
  end

  defmodule AnswerShell do
    @moduledoc false
    def prompt(_message), do: "  MyDomain \n"
  end

  setup do
    on_exit(fn -> Mix.shell(Mix.Shell.Process) end)
    :ok
  end

  test "trims the answer" do
    Mix.shell(AnswerShell)
    assert Mix.Brando.prompt("+ Enter domain") == "MyDomain"
  end

  # `Mix.Shell.IO.prompt/1` returns `IO.gets/1`'s `:eof` when stdin is closed.
  # Piped into `String.trim/1` that raised a `FunctionClauseError` from inside
  # `String`, naming neither the generator nor the question it had asked — which
  # is how it reached CI, where it read as an inscrutable crash in the installer.
  test "refuses to guess when there is no one to answer" do
    Mix.shell(EofShell)

    assert_raise Mix.Error, ~r/No answer given for:.*\+ Enter domain/s, fn ->
      Mix.Brando.prompt("+ Enter domain")
    end
  end
end
