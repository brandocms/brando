defmodule Mix.Brando.Igniter.InstallTenancyTest do
  # Synchronous: these projects configure `:brando` in config/config.exs, which
  # Igniter's formatter puts into Brando's application environment (see
  # Brando.IgniterCase), and the interactive install sets the global Mix.shell.
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Tasks.Brando.Install

  defp project(files \\ %{}), do: IgniterCase.install_project(files)

  defp install(igniter, args \\ []), do: Igniter.compose_task(igniter, Install, args)

  test "interactive choices are opt-in and supplied answers are not requested again" do
    Mix.shell(Mix.Shell.Process)
    send(self(), {:mix_shell_input, :prompt, "guided-studio"})
    igniter = project() |> install(["--interactive", "--tenancy-mode", "single"])
    assert igniter.issues == []
    assert_received {:mix_shell, :prompt, ["+ Site key [studio]"]}
    refute_received {:mix_shell, :prompt, _}
    assert IgniterCase.source(igniter, "config/brando.exs") =~ ~s(site_key: "guided-studio")
  end

  test "explicit tenancy changes update existing base config and remove a stale site key" do
    for config <- [
          ~s(config :brando, tenancy_mode: :single, site_key: "old-site"),
          ~s(config :brando, :tenancy_mode, :single\nconfig :brando, :site_key, "old-site")
        ] do
      result = project(%{"config/config.exs" => "import Config\n" <> config}) |> install(["--tenancy-mode", "none"])
      assert result.issues == []
      assert {:ok, _, %{mode: :none, site_key: nil}} = Mix.Brando.Igniter.Install.Configuration.existing_tenancy(result)
      refute IgniterCase.source(result, "config/config.exs") =~ "old-site"
      rerun = install(result)
      assert rerun.issues == []
    end
  end

  test "conflicting or dynamic tenancy configuration is rejected without choosing a value" do
    for config <- [
          ~s|config :brando, tenancy_mode: System.get_env("TENANCY")|,
          ~s(config :brando, tenancy_mode: :single\nconfig :brando, tenancy_mode: :multi)
        ] do
      result = project(%{"config/config.exs" => "import Config\n" <> config}) |> install()
      assert Enum.any?(result.issues, &String.contains?(&1, "unambiguously"))
      Igniter.Test.assert_unchanged(result)
    end
  end
end
