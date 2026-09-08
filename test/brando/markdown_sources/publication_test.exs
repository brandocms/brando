defmodule Brando.MarkdownSources.PublicationTest do
  use Brando.ConnCase, async: false
  alias Brando.MarkdownSources.{Connection, Publication, Source, Version}
  alias Brando.SSG.{Builds, Deploy}
  alias Brando.Tenant.{Cache, Registry}

  defmodule Builder do
    def build(site, environment, opts) do
      html =
        Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fn ->
          source = Brando.MarkdownSources.list_sources() |> hd()
          Brando.MarkdownSources.render(%{source_id: source.id, policy: :follow, version_id: nil})
        end)

      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), html)
      {:ok, %{file_count: 1, total_size: byte_size(html), url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:authorization_mode, :legacy)
    root = Path.join(System.tmp_dir!(), "markdown-publish-#{System.unique_integer([:positive])}")
    put_test_env(:sites_path, root)
    Cache.clear()
    owner = Brando.Factory.insert(:random_user, role: :superuser)

    {:ok, site} =
      Registry.create_site(%{
        name: "Markdown site",
        key: "markdown-test",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: "deploy@example.test:/srv/docs"}
      })

    {:ok, environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    prefix = Brando.Tenant.prefix(site, environment)
    # Clone the actual migrated content tables inside the sandbox transaction.
    # LIKE deliberately leaves public registry/auth tables shared.
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))
    {:ok, tables} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
    for table <- tables, do: Repo.query!(~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)

    put_test_env(:markdown_sources,
      connections: %{
        "docs" => %{
          repository: "acme/docs",
          repository_id: 42,
          secret: String.duplicate("s", 40),
          destinations: [prefix],
          auto_deploy: true,
          publisher_id: owner.id
        }
      }
    )

    Brando.Tenant.put_prefix(prefix)
    source = Brando.Repo.insert!(%Source{name: "Docs", connection: "docs", ref: "refs/heads/main", path: "readme.md"})
    first = version(source, "a", "first")
    source = Brando.Repo.update!(Ecto.Changeset.change(source, latest_version_id: first.id))
    {:ok, connection} = Connection.current("docs")

    args =
      %{
        source_id: source.id,
        version_id: first.id,
        source_revision: source.publication_sequence,
        connection: "docs",
        generation: Connection.generation(connection)
      }
      |> Brando.Tenant.Job.attach()
      |> Jason.encode!()
      |> Jason.decode!()

    on_exit(fn ->
      Brando.Tenant.put_prefix(nil)
      Cache.clear()
      File.rm_rf(root)
    end)

    %{source: source, owner: owner, args: args, site: site, environment: environment, root: root}
  end

  defp version(source, commit, text),
    do:
      Brando.Repo.insert!(%Version{
        source_id: source.id,
        commit: String.duplicate(commit, 40),
        markdown: text,
        html: text,
        content_hash: text,
        repository: "acme/docs",
        path: source.path
      })

  defp build(c) do
    Oban.Testing.with_testing_mode(:manual, fn -> assert :ok = Publication.publish(c.args) end)
    source = Brando.MarkdownSources.get_source(c.source.id)
    build = Builds.get_build(source.build_id)
    assert build.auto_deploy
    assert build.environment_id == c.environment.id
    File.mkdir_p!(build.build_path)
    File.write!(Path.join(build.build_path, "index.html"), "published Markdown")
    {:ok, build} = Builds.update(build, %{status: :ready})
    Builds.get_build(build.id)
  end

  test "the queued SSG worker builds and automatically deploys; retries do not create duplicate builds", c do
    destination = Path.join(c.root, "deployed")
    File.mkdir_p!(destination)
    {:ok, _} = Registry.update_site(c.site, %{deploy_config: %{strategy: :rsync, target: destination}})
    put_test_env(:ssg_builder, Builder)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = Publication.publish(c.args)
      assert :ok = Publication.publish(c.args)
    end)

    build_id = Brando.MarkdownSources.get_source(c.source.id).build_id
    assert length(Builds.list_builds(c.site)) == 1
    assert :ok = perform_job(Brando.Worker.SSGBuild, %{"build_id" => build_id})
    assert Builds.get_build(build_id).status == :deployed
    assert File.read!(Path.join(destination, "index.html")) == "first"
  end

  test "automatic publication queues an SSG artifact and deploys only in its authorized live environment", c do
    build = build(c)
    assert Publication.current?(build)
    assert {:ok, deployed} = Deploy.deploy(build, creator: c.owner, runner: fn "rsync", _, _ -> {"ok", 0} end)
    assert deployed.status == :deployed
    assert Brando.MarkdownSources.get_source(c.source.id).publication_status == "Build queued"
    refute inspect(build.markdown_context) =~ String.duplicate("s", 40)
  end

  test "a newer source cancels an old artifact; content-identical commits do not cancel it", c do
    build = build(c)
    identical = version(c.source, "b", "first")
    Brando.Repo.update!(Ecto.Changeset.change(c.source, latest_version_id: identical.id))
    assert Publication.current?(build)
    changed = version(c.source, "c", "changed")
    Brando.Repo.update!(Ecto.Changeset.change(c.source, latest_version_id: changed.id))
    refute Publication.current?(build)

    assert {:error, :markdown_publication_superseded} =
             Deploy.deploy(build,
               creator: c.owner,
               runner: fn _, _, _ -> flunk("superseded artifact reached deployment") end
             )
  end

  test "revocation and tenant redirection cancel queued work", c do
    build = build(c)
    assert {:cancel, :publication_superseded} = Publication.publish(Map.put(c.args, "generation", "old"))
    Brando.Repo.update!(Ecto.Changeset.change(c.owner, active: false))
    refute Publication.current?(build)
    Application.put_env(:brando, :markdown_sources, connections: %{})
    assert {:cancel, :publication_superseded} = Publication.publish(c.args)
  end

  test "a failed external deployment preserves the previous deployed artifact", c do
    first = build(c)
    {:ok, _} = Deploy.deploy(first, creator: c.owner, runner: fn _, _, _ -> {"ok", 0} end)
    source = Brando.Repo.update!(Ecto.Changeset.change(c.source, publication_sequence: 1))
    second = build(%{c | source: source, args: Map.put(c.args, "source_revision", 1)})

    assert {:error, {:rsync_failed, 1, "failed"}} =
             Deploy.deploy(second, creator: c.owner, runner: fn _, _, _ -> {"failed", 1} end)

    assert Builds.get_build(first.id).status == :deployed
    assert Builds.get_build(second.id).status == :ready

    assert {:error, :markdown_publication_superseded} =
             Deploy.deploy(first, creator: c.owner, runner: fn _, _, _ -> flunk("older build deployed") end)
  end
end
