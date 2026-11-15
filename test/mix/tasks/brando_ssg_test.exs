defmodule BrandoIntegrationWeb.SSG do
  import Brando.SSG

  urls :pages do
    ["/"]
  end
end

defmodule Mix.Tasks.Brando.SsgTest do
  use Brando.ConnCase

  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Test.SSGEndpoint

  setup do
    put_test_env(:tenancy_mode, :none)
    Mix.Task.reenable("brando.ssg")
    Mix.Task.reenable("run")

    root = Path.join(System.tmp_dir!(), "brando-ssg-task-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "retains a non-tenant, non-interactive dry-run workflow", %{root: root} do
    output = Path.join(root, "output")
    refute File.exists?(output)

    assert :ok =
             Mix.Tasks.Brando.Ssg.run([
               "--force",
               "--dry-run",
               "--output",
               output
             ])

    refute File.exists?(output)
  end

  test "builds from the endpoint's listener on the port it is configured with, without its watchers",
       %{root: root} do
    receiver = SSGEndpoint.start(fn _request -> {200, "<main>home</main>"} end)
    refute receiver.port == 4000
    # The configuration the task starts the endpoint from, in a project
    config = Application.get_env(:brando, SSGEndpoint)
    Application.put_env(:brando, SSGEndpoint, Keyword.put(config, :watchers, vite: {Brando.Vite, :watch, [root]}))
    put_test_env(:endpoint_module, SSGEndpoint)
    put_test_env(:media_path, Path.join(root, "media"))
    output = Path.join(root, "output")

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    assert :ok = Mix.Tasks.Brando.Ssg.run(["--force", "--no-compile-assets", "--output", output])

    assert_received {:webhook_request, %{path: "/", headers: %{"host" => host}}}
    assert host == "127.0.0.1:#{receiver.port}"
    assert File.read!(Path.join(output, "index.html")) =~ "home"
    assert Application.get_env(:brando, SSGEndpoint)[:watchers] == []
    assert Application.get_env(:phoenix, :serve_endpoints)
  end

  test "says what is missing when the endpoint has no HTTP listener", %{root: root} do
    # The test application's endpoint runs with server: false
    put_test_env(:media_path, Path.join(root, "media"))
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    assert_raise Mix.Error, ~r/BrandoIntegrationWeb.Endpoint has no HTTP listener/, fn ->
      Mix.Tasks.Brando.Ssg.run(["--force", "--no-compile-assets", "--output", Path.join(root, "output")])
    end
  end

  test "with several sites, writes under the site's own ssg directory by default", %{root: root} do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    Cache.clear()
    on_exit(&Cache.clear/0)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    assert :ok = Mix.Tasks.Brando.Ssg.run(["--force", "--dry-run", "--site", site.key])

    expected = Path.join([root, "sites", site.key, "ssg", "manual"])
    assert_received {:mix_shell, :info, ["Output: " <> ^expected]}
  end
end
