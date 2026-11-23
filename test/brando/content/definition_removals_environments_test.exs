defmodule Brando.Content.DefinitionRemovalsEnvironmentsTest do
  # brandocms/brando#3540: a release that removes a var from a module both
  # environments of a site have counts and resolves the blocks of the
  # environment it plans, and changes only that one.
  use Brando.ConnCase, async: false

  @moduletag :capture_log

  alias Brando.Content.{Block, Definitions, Module, Var}
  alias Brando.Content.Definitions.{Release, ReleaseStatus}
  alias Brando.Repo
  alias Brando.Tenant

  @production "tenant_acme_production"
  @staging "tenant_acme_staging"

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-removals-environments-#{System.unique_integer([:positive])}")
    release = Path.join(root, "release")
    File.mkdir_p!(release)
    source = File.read!("test/fixtures/definitions/hero.exs.txt")
    File.write!(Path.join(release, "hero.exs"), source)

    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:tenancy_mode, :multi, global: true)
    put_test_env(:authorization_mode, :legacy, global: true)
    put_test_env(Definitions, release_path: release)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()
    ReleaseStatus.clear()

    on_exit(fn ->
      ReleaseStatus.clear()
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      File.rm_rf(root)
    end)

    user = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)

    {:ok, _site} =
      Brando.Tenant.Setup.create_site(
        %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
        user,
        environments: [
          %{name: "Production", key: "production", live: true},
          %{name: "Staging", key: "staging", live: false}
        ],
        seed: false
      )

    # Both environments have the hero, and a block in each holds its `theme`
    holders =
      Map.new([@production, @staging], fn prefix ->
        Tenant.with_prefix(prefix, fn ->
          {:ok, _} = Release.apply(:all, user: user.id)
          {prefix, block_with_theme!(user)}
        end)
      end)

    File.write!(
      Path.join(release, "hero.exs"),
      source
      |> String.replace(~r/\n  vars do\n.*?\n  end\n/s, "\n")
      |> String.replace(" class={@theme}", "")
    )

    %{user: user, holders: holders}
  end

  defp block_with_theme!(user) do
    module = Repo.get_by!(Module, uid: "hero-test")

    block =
      Repo.insert!(%Block{uid: Brando.Utils.generate_uid(), type: :module, module_id: module.id, creator_id: user.id})

    Repo.insert!(%Var{block_id: block.id, key: "theme", type: :select, label: %{"en" => "Theme"}, value: "dark"})
    block
  end

  defp theme(prefix, block), do: Tenant.with_prefix(prefix, fn -> Repo.get_by(Var, block_id: block.id, key: "theme") end)

  defp module_vars(prefix),
    do: Tenant.with_prefix(prefix, fn -> Repo.preload(Repo.get_by!(Module, uid: "hero-test"), :vars).vars end)

  test "plans, applies and resolves only the named environment", c do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    info = fn line -> Agent.update(agent, &[line | &1]) end
    :ok = Release.status(site: "acme", environment: "production", user: c.user.id, info: info)
    text = agent |> Agent.get(& &1) |> Enum.reverse()

    assert "  update module Hero (hero-test): removes var theme (1 of 1 blocks hold it, 0 entries)" in text
    resolve = Enum.find_value(text, &(String.starts_with?(&1, "    resolve: ") && String.trim_leading(&1)))

    assert resolve ==
             "resolve: mix brando.modules resolve --uid hero-test --user #{c.user.id} " <>
               "--site acme --environment production --drop var:theme --apply"

    Tenant.with_prefix(@production, fn -> {:ok, _} = Release.apply(:all, user: c.user.id, wait: false) end)
    assert module_vars(@production) == []
    assert [%{key: "theme"}] = module_vars(@staging)
    assert theme(@production, c.holders[@production]).value == "dark"

    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)
    Mix.Task.reenable("brando.modules")
    resolve |> String.split() |> Enum.drop(3) |> Mix.Tasks.Brando.Modules.run()

    assert theme(@production, c.holders[@production]) == nil
    assert theme(@staging, c.holders[@staging]).value == "dark"
  end

  # brandocms/brando#3844
  test "a rename moves the values of the environment it applies to, and no other's", c do
    File.write!(
      Path.join(Release.path(), "hero.exs"),
      "test/fixtures/definitions/hero.exs.txt"
      |> File.read!()
      |> String.replace("var :theme, :select do", ~s(var :tone, :select do\n      renamed_from "theme"))
      |> String.replace("@theme", "@tone")
    )

    Tenant.with_prefix(@production, fn -> {:ok, _} = Release.apply(:all, user: c.user.id, wait: false) end)

    tone = Tenant.with_prefix(@production, fn -> Repo.get_by(Var, block_id: c.holders[@production].id, key: "tone") end)
    assert tone.value == "dark"
    assert theme(@production, c.holders[@production]) == nil
    assert theme(@staging, c.holders[@staging]).value == "dark"
    assert [%{key: "theme"}] = module_vars(@staging)
  end
end
