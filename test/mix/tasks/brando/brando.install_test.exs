defmodule Mix.Tasks.Brando.GenerateTest do
  use ExUnit.Case

  setup do
    Mix.shell(Mix.Shell.Process)
    :ok
  end

  test "configures Swoosh, which Brando depends on, so the application starts" do
    result =
      Brando.IgniterCase.phoenix_project(module: "MailInstallStudio")
      |> Igniter.compose_task("brando.install", ["--yes", "--tenancy-mode", "none"])

    assert Brando.IgniterCase.source(result, "config/config.exs") =~ "api_client: Swoosh.ApiClient.Req"
  end

  test "parses valid installer tenancy options" do
    assert Mix.Tasks.Brando.Install.parse_tenancy_options!([]) == %{
             mode: :none,
             site_key: nil
           }

    assert Mix.Tasks.Brando.Install.parse_tenancy_options!(
             tenancy_mode: "single",
             site_key: "photo-blog"
           ) == %{mode: :single, site_key: "photo-blog"}

    assert Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "multi") == %{
             mode: :multi,
             site_key: nil
           }
  end

  test "writes single-site tenancy and the template's image defaults to config/brando.exs" do
    config =
      Brando.IgniterCase.phoenix_project(app: :photo_blog, module: "PhotoBlog")
      |> Igniter.compose_task("brando.install", ["--yes", "--tenancy-mode", "single", "--site-key", "photo-blog"])
      |> Brando.IgniterCase.source("config/brando.exs")

    assert config =~ "tenancy_mode: :single"
    assert config =~ ~s(site_key: "photo-blog")
    assert config =~ "processor_module: Brando.Images.Processor.Vix"
    assert config =~ ~s({"xlarge", "2100w"})
  end

  test "guides interactive single-site setup and supplies the project key default" do
    send(self(), {:mix_shell_input, :prompt, "2"})
    send(self(), {:mix_shell_input, :prompt, ""})

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!([tenancy_prompt: true], "photo-blog") == %{
             mode: :single,
             site_key: "photo-blog"
           }

    assert_received {:mix_shell, :prompt, [mode_prompt]}
    assert mode_prompt =~ "Choose tenancy mode"
    assert mode_prompt =~ "2. single"
    assert_received {:mix_shell, :prompt, [site_prompt]}
    assert site_prompt =~ "Site key [photo-blog]"
  end

  test "supports non-interactive installs without tenancy flags" do
    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!(
             [tenancy_prompt: false],
             "photo-blog"
           ) == %{mode: :none, site_key: nil}

    refute_received {:mix_shell, :prompt, _message}
  end

  test "rejects incomplete or contradictory installer tenancy options" do
    assert_raise Mix.Error, ~r/--site-key is required/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "single")
    end

    assert_raise Mix.Error, ~r/--site-key can only be used/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(site_key: "photo-blog")
    end

    assert_raise Mix.Error, ~r/Invalid --tenancy-mode/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "global")
    end
  end
end
