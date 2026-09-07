defmodule Mix.Brando.Install.OptionsTest do
  use ExUnit.Case, async: false

  alias Mix.Brando.Install.Options

  defmodule ClosedInput do
    @moduledoc false
    def prompt(_message), do: raise("The installer must not prompt")
  end

  defmodule EofInput do
    @moduledoc false
    def prompt(_message), do: :eof
  end

  test "defaults to none without consulting stdin" do
    shell = Mix.shell()
    on_exit(fn -> Mix.shell(shell) end)
    Mix.shell(ClosedInput)

    assert Options.tenancy([]) == {:ok, %{mode: :none, site_key: nil}}
    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!([], "studio") == %{mode: :none, site_key: nil}

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!([tenancy_prompt: false], "studio") ==
             %{mode: :none, site_key: nil}
  end

  test "omitted options preserve an existing tenancy choice" do
    for existing <- [%{mode: :none, site_key: nil}, %{mode: :single, site_key: "studio"}, %{mode: :multi, site_key: nil}] do
      assert Options.tenancy([], existing) == {:ok, existing}
      assert Options.tenancy([tenancy_prompt: false], existing) == {:ok, existing}
    end
  end

  test "interactive setup asks for a missing site key and respects supplied choices" do
    shell = Mix.shell()
    on_exit(fn -> Mix.shell(shell) end)
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, "my-studio"})

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!(
             [interactive: true, tenancy_mode: "single"],
             "studio"
           ) == %{mode: :single, site_key: "my-studio"}

    assert_received {:mix_shell, :prompt, ["+ Site key [studio]"]}
    refute_received {:mix_shell, :prompt, _message}

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!(
             [interactive: true, tenancy_mode: "multi"],
             "studio"
           ) == %{mode: :multi, site_key: nil}

    refute_received {:mix_shell, :prompt, _message}
  end

  test "interactive setup guides the mode choice and can be explicitly suppressed" do
    shell = Mix.shell()
    on_exit(fn -> Mix.shell(shell) end)
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, ""})

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!([interactive: true], "studio") ==
             %{mode: :none, site_key: nil}

    assert_received {:mix_shell, :prompt, [message]}
    assert message =~ "Choose tenancy mode"

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!(
             [interactive: true, tenancy_prompt: false],
             "studio"
           ) == %{mode: :none, site_key: nil}

    refute_received {:mix_shell, :prompt, _message}
  end

  test "guided setup validates the suggested site key and asks again when it is invalid" do
    shell = Mix.shell()
    on_exit(fn -> Mix.shell(shell) end)
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, "single"})
    send(self(), {:mix_shell_input, :prompt, ""})
    send(self(), {:mix_shell_input, :prompt, "valid-site"})

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!([interactive: true], "invalid--default") ==
             %{mode: :single, site_key: "valid-site"}

    assert_received {:mix_shell, :error, [message]}
    assert message =~ "single hyphens"
  end

  test "explicit interactive mode reports closed stdin instead of assuming an answer" do
    shell = Mix.shell()
    on_exit(fn -> Mix.shell(shell) end)
    Mix.shell(EofInput)

    assert_raise Mix.Error, ~r/stdin is closed/, fn ->
      Mix.Tasks.Brando.Install.resolve_tenancy_options!([interactive: true], "studio")
    end
  end

  test "explicit mode replaces the default and does not inherit an old site key" do
    existing = %{mode: :single, site_key: "studio"}
    assert Options.tenancy([tenancy_mode: "multi"], existing) == {:ok, %{mode: :multi, site_key: nil}}
    assert Options.tenancy([tenancy_mode: "none"], existing) == {:ok, %{mode: :none, site_key: nil}}

    assert Options.tenancy([tenancy_mode: "single"], existing) ==
             {:error, "--site-key is required with --tenancy-mode single"}

    assert Options.tenancy(tenancy_mode: "single", site_key: "my-studio") ==
             {:ok, %{mode: :single, site_key: "my-studio"}}
  end

  test "site keys require an explicit single mode, including on reruns" do
    existing = %{mode: :single, site_key: "studio"}

    for options <- [
          [site_key: "new-studio"],
          [tenancy_mode: "none", site_key: "studio"],
          [tenancy_mode: "multi", site_key: "studio"]
        ] do
      assert Options.tenancy(options, existing) == {:error, "--site-key can only be used with --tenancy-mode single"}
    end
  end

  test "rejects invalid site keys and modes" do
    for key <- ["", "Studio", "two--hyphens", "../studio"] do
      assert {:error, message} = Options.tenancy(tenancy_mode: "single", site_key: key)
      assert message =~ "lowercase, URL-safe key"
    end

    assert {:error, message} = Options.tenancy(tenancy_mode: "typo")
    assert message =~ "expected none, single, or multi"
  end
end
