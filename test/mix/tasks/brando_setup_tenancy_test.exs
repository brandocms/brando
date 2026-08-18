defmodule Mix.Tasks.BrandoSetupTenancyTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Brando.Setup.Tenancy

  @config_path "config/brando.exs"
  @router_path "lib/legacy_app_web/router.ex"
  @tenant_migration_path "priv/repo/tenant_migrations/20260816002300_add_shared_content_library.exs"

  @config """
  import Config

  config :brando,
    app_module: LegacyApp,
    repo_module: LegacyApp.Repo
  """

  @router """
  defmodule LegacyAppWeb.Router do
    use LegacyAppWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :put_secure_browser_headers
      plug Brando.Plug.Identity
      plug Brando.Plug.Navigation, key: "main", as: :navigation
    end

    pipeline :browser_api do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :put_secure_browser_headers
    end
  end
  """

  test "configures single-site tenancy and recognized browser pipelines" do
    igniter = setup_tenancy(["--mode", "single", "--site-key", "legacy-site"])
    config = source(igniter, @config_path)
    router = source(igniter, @router_path)

    assert config =~ "tenancy_mode: :single"
    assert config =~ ~s(site_key: "legacy-site")
    assert count(router, "plug(Brando.Plug.Tenant)") == 2
    assert before?(router, "plug(Brando.Plug.Tenant)", "plug(Brando.Plug.Identity)")

    assert_creates(igniter, @tenant_migration_path, fn migration ->
      assert migration =~ "defmodule Brando.Repo.TenantMigrations.AddSharedContentLibrary"
    end)

    assert_has_notice(igniter, &String.contains?(&1, "No database"))
    assert_has_notice(igniter, &String.contains?(&1, "mix brando.migrate_to_tenant --site-key=legacy-site"))
    # The steps have to name what the operator would otherwise have to discover.
    assert_has_notice(igniter, &String.contains?(&1, "mix brando.migrate"))
    assert_has_notice(igniter, &String.contains?(&1, ":shared_tables"))
    assert_has_notice(igniter, &String.contains?(&1, "pg_dump"))
    assert_has_notice(igniter, &String.contains?(&1, "/admin/sites"))
    assert_has_notice(igniter, &String.contains?(&1, "--move"))
    assert_has_notice(igniter, &String.contains?(&1, "Content tables need no tenant migrations"))
  end

  test "configures multi-site tenancy without a site key" do
    existing_single_config =
      @config <>
        """

        config :brando,
          tenancy_mode: :single,
          site_key: "legacy-site"
        """

    igniter = setup_tenancy(["--mode", "multi"], %{@config_path => existing_single_config})
    config = source(igniter, @config_path)

    assert config =~ "tenancy_mode: :multi"
    refute config =~ "site_key:"
    assert_has_notice(igniter, &String.contains?(&1, "prepared for `multi` mode"))
    assert_has_notice(igniter, &String.contains?(&1, "mix brando.migrate_to_tenant --site-key=my-site"))
  end

  test "is idempotent" do
    second_pass =
      ["--mode", "single", "--site-key", "legacy-site"]
      |> setup_tenancy()
      |> apply_igniter!()
      |> include_test_files()
      |> run_task(["--mode", "single", "--site-key", "legacy-site"])

    assert_unchanged(second_pass)
  end

  test "warns when no Phoenix router can be found" do
    igniter =
      [app_name: :legacy_app, files: %{@config_path => @config}]
      |> test_project_with_files()
      |> run_task(["--mode", "multi"])

    assert_has_warning(igniter, &String.contains?(&1, "No Phoenix router could be found"))
  end

  test "warns when a router has no browser pipeline" do
    router = """
    defmodule LegacyAppWeb.Router do
      use LegacyAppWeb, :router

      pipeline :api do
        plug :accepts, ["json"]
      end
    end
    """

    igniter = setup_tenancy(["--mode", "multi"], %{@router_path => router})

    assert_has_warning(igniter, &String.contains?(&1, "has no `:browser` pipeline"))
  end

  test "rejects incomplete and contradictory tenancy options" do
    # --yes opts out of the prompts, so a missing option stays an error.
    missing_key = setup_tenancy(["--mode", "single", "--yes"])
    missing_mode = setup_tenancy(["--yes"])
    invalid_key = setup_tenancy(["--mode", "single", "--site-key", "Not Valid"])
    multi_key = setup_tenancy(["--mode", "multi", "--site-key", "legacy-site"])
    invalid_mode = setup_tenancy(["--mode", "none"])

    assert_has_issue(missing_key, &String.contains?(&1, "--site-key is required"))
    assert_has_issue(missing_mode, &String.contains?(&1, "--mode is required"))
    assert_has_issue(invalid_key, &String.contains?(&1, "lowercase, URL-safe key"))
    assert_has_issue(multi_key, &String.contains?(&1, "can only be used with --mode single"))
    assert_has_issue(invalid_mode, &String.contains?(&1, "expected single or multi"))
  end

  test "asks for mode and site key when they are not passed" do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    send(self(), {:mix_shell_input, :prompt, "single"})
    send(self(), {:mix_shell_input, :prompt, "by"})

    igniter = setup_tenancy([])

    assert_has_patch(igniter, @config_path, """
    + |  tenancy_mode: :single,
    """)

    assert_has_patch(igniter, @config_path, """
    + |  site_key: "by"
    """)
  end

  test "re-asks until the site key is valid" do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    send(self(), {:mix_shell_input, :prompt, "Not Valid"})
    send(self(), {:mix_shell_input, :prompt, "second-try"})

    igniter = setup_tenancy(["--mode", "single"])

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "lowercase, URL-safe key"

    assert_has_patch(igniter, @config_path, """
    + |  site_key: "second-try"
    """)
  end

  defp setup_tenancy(argv, overrides \\ %{}) do
    files =
      %{
        @config_path => @config,
        @router_path => @router
      }
      |> Map.merge(overrides)

    [
      app_name: :legacy_app,
      files: files
    ]
    |> test_project_with_files()
    |> run_task(argv)
  end

  defp test_project_with_files(opts) do
    opts
    |> test_project()
    |> include_test_files()
  end

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, fn path, igniter ->
      Igniter.include_existing_file(igniter, path)
    end)
  end

  defp run_task(igniter, argv) do
    Igniter.Mix.Task.configure_and_run(igniter, Tenancy, argv)
  end

  defp source(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp count(content, pattern), do: content |> String.split(pattern) |> length() |> Kernel.-(1)

  defp before?(content, left, right) do
    :binary.match(content, left) < :binary.match(content, right)
  end
end
