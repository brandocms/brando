defmodule Brando.SSG.ContentChangesTest do
  # Marks are written after the commit, by a separate process for a
  # transaction begun on the repo itself, and told on the build topic
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Brando.Activity.Event
  alias Brando.Assets.SiteAssets
  alias Brando.Environments
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.SSG.Builds
  alias Brando.SSG.ContentChanges
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGBuild

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule SuccessfulBuilder do
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")
      {:ok, %{file_count: 1, total_size: 5, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  defmodule HomeOnly do
    @moduledoc false
    import Brando.SSG

    urls :pages do
      ["/"]
    end
  end

  # Brando.SSG with this module's URL, and no assets or media to copy
  defmodule RenderingBuilder do
    def build(site, environment, opts) do
      empty = Path.join(System.tmp_dir!(), "brando-content-changes-#{System.unique_integer([:positive])}")
      File.mkdir_p!(empty)

      try do
        Brando.SSG.build(
          site,
          environment,
          opts ++ [ssg_module: HomeOnly, static_path: empty, media_path: empty, site_files: false]
        )
      after
        File.rm_rf(empty)
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-content-changes-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    user = Factory.insert(:random_user, role: :superuser)
    site = site!("static-changes", :static)
    production = environment!(site, "production", true)
    staging = environment!(site, "staging", false)
    dynamic = site!("dynamic-changes", :dynamic)
    dynamic_production = environment!(dynamic, "production", true)
    Phoenix.PubSub.subscribe(Brando.pubsub(), Builds.topic(site))

    %{
      user: user,
      site: Registry.get_site(site.id),
      production: production,
      staging: staging,
      dynamic: dynamic,
      dynamic_production: dynamic_production
    }
  end

  describe "a save" do
    test "marks its environment of a static site, and no other environment or site", c do
      page = page!(c.site, c.production, c.user)
      started = DateTime.utc_now()

      update_page!(c.site, c.production, page, c.user)

      assert_receive {:ssg_content_changed, production_id}
      assert production_id == c.production.id
      assert DateTime.compare(ContentChanges.changed_at(c.production), started) == :gt
      refute ContentChanges.changed_at(c.staging)

      dynamic_page = page!(c.dynamic, c.dynamic_production, c.user)
      update_page!(c.dynamic, c.dynamic_production, dynamic_page, c.user)
      refute ContentChanges.changed_at(c.dynamic_production)
    end

    test "in a transaction marks once, after it has committed", c do
      page = page!(c.site, c.production, c.user)
      other = page!(c.site, c.production, c.user)

      {marks, {:ok, :saved}} =
        counting_marks(fn ->
          Brando.Repo.transaction(fn ->
            update_page!(c.site, c.production, page, c.user)
            update_page!(c.site, c.production, other, c.user)
            refute ContentChanges.changed_at(c.production)
            :saved
          end)
        end)

      assert marks == 1
      assert ContentChanges.changed_at(c.production)
    end

    test "rolled back marks nothing", c do
      page = page!(c.site, c.production, c.user)

      assert {:error, :undone} =
               Brando.Repo.transaction(fn ->
                 update_page!(c.site, c.production, page, c.user)
                 Brando.Repo.rollback(:undone)
               end)

      refute ContentChanges.changed_at(c.production)
    end

    test "in a transaction begun on the repo itself is marked once it has ended, dated after it", c do
      page = page!(c.site, c.production, c.user)

      {:ok, ended} =
        Brando.Repo.repo().transaction(fn ->
          update_page!(c.site, c.production, page, c.user)
          update_page!(c.site, c.production, page, c.user)
          refute ContentChanges.changed_at(c.production)
          DateTime.utc_now()
        end)

      assert_receive {:ssg_content_changed, _}, 2_000
      assert DateTime.compare(ContentChanges.changed_at(c.production), ended) == :gt
      assert title(c.site, c.production, page) == "Saved"
    end

    # The waiter on the test's connection, the transaction on a session of
    # its own: the waiter cannot wait for the connection, only for the lock
    test "in a transaction begun on the repo itself is marked only once that has ended", c do
      session = own_session()
      test = self()

      saver =
        in_session(session, fn ->
          Brando.Repo.repo().transaction(fn ->
            ContentChanges.touch_environment(c.production)
            send(test, :touched)

            receive do
              :commit -> :ok
            end
          end)
        end)

      assert_receive :touched
      assert waiter_waiting?(session)
      refute_received {:ssg_content_changed, _}

      send(saver.pid, :commit)
      assert {:ok, :ok} = Task.await(saver)
      assert_receive {:ssg_content_changed, production_id}, 2_000
      assert production_id == c.production.id
    end

    test "in a transaction begun on the repo itself is saved when no waiter can start", c do
      page = page!(c.site, c.production, c.user)
      waiters = Brando.SSG.ContentChanges.TaskSupervisor
      :ok = Supervisor.terminate_child(Brando.Supervisor, waiters)
      on_exit(fn -> Supervisor.restart_child(Brando.Supervisor, waiters) end)

      capture_log(fn ->
        assert {:ok, _} = Brando.Repo.repo().transaction(fn -> update_page!(c.site, c.production, page, c.user) end)
      end)

      assert title(c.site, c.production, page) == "Saved"
    end

    # A build that reads the content once it is marked must not find it as
    # the cache held it before the save
    test "is marked after the evictions that go with it", c do
      page = page!(c.site, c.production, c.user)
      preserve_query_cache(Page)

      Tenant.with_prefix(Tenant.prefix(c.site, c.production), fn ->
        key = Brando.Cache.Query.hash_query({:list, "pages", :marked})

        {cached, _} =
          at_marks(
            fn -> Brando.Cache.Query.get(key) end,
            fn ->
              Brando.Cache.Query.put(key, :as_it_was)
              Brando.Cache.Query.evict({:ok, page})

              Brando.Repo.transaction(fn ->
                Brando.Cache.Query.evict({:ok, page})
                # As another process reading before the commit caches it
                Brando.Cache.Query.put(key, :as_it_was)
              end)
            end
          )

        assert [_ | _] = cached
        assert Enum.all?(cached, &is_nil/1)
      end)
    end

    # A row lock or table lock another session holds on the marks
    test "made outside a transaction waits only a moment for another session's lock on the marks", c do
      session = own_session()
      test = self()

      holder =
        in_session(session, fn ->
          Brando.Repo.repo().transaction(fn ->
            Brando.Repo.repo().query!("LOCK TABLE public.ssg_content_changes IN EXCLUSIVE MODE")
            send(test, :locked)

            receive do
              :release -> :ok
            end
          end)
        end)

      assert_receive :locked
      toucher = Task.async(fn -> ContentChanges.touch_environment(c.production) end)

      try do
        assert {:ok, :ok} = Task.yield(toucher, 5_000), "the save waited for the lock"
      after
        send(holder.pid, :release)
        Task.await(holder)
      end

      refute ContentChanges.changed_at(c.production)
    end

    test "made outside a transaction leaves the lock wait of an enclosing transaction as it was", c do
      repo = Brando.Repo.repo()
      before = repo.query!("SHOW lock_timeout").rows

      ContentChanges.touch_environment(c.production)

      assert ContentChanges.changed_at(c.production)
      assert repo.query!("SHOW lock_timeout").rows == before
    end

    test "rolled back in a transaction begun on the repo itself stays undone, and raises nothing", c do
      page = page!(c.site, c.production, c.user)

      assert {:error, :undone} =
               Brando.Repo.repo().transaction(fn ->
                 update_page!(c.site, c.production, page, c.user)
                 Brando.Repo.repo().rollback(:undone)
               end)

      # The mark errs towards changed: its waiter cannot tell a rollback
      assert_receive {:ssg_content_changed, _}, 2_000
      assert title(c.site, c.production, page) == "Page"
    end

    test "with no tenant prefix marks nothing", c do
      Tenant.put_prefix(nil)
      Brando.Cache.Query.evict_all(Page)
      Brando.Cache.rebuild_after_commit(:globals)

      refute marks?()
      refute_received {:ssg_content_changed, _}
      assert c.production
    end

    test "to a shared table or the activity log marks nothing", c do
      Tenant.with_prefix(Tenant.prefix(c.site, c.production), fn ->
        ContentChanges.touch("users")
        ContentChanges.touch("activity_events")
      end)

      refute marks?()
    end

    test "rebuilding a site cache marks", c do
      Tenant.with_prefix(Tenant.prefix(c.site, c.production), fn -> Brando.Cache.rebuild_after_commit(:globals) end)

      assert ContentChanges.changed_at(c.production)
    end

    test "made by a scheduled publication when its time comes marks", c do
      prefix = Tenant.prefix(c.site, c.production)
      publish_at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
      page = page!(c.site, c.production, c.user, status: :pending, publish_at: publish_at)

      assert [%{id: id, result: :ok}] = Tenant.with_prefix(prefix, fn -> Brando.Publisher.sweep() end)
      assert id == page.id
      assert ContentChanges.changed_at(c.production)
    end
  end

  test "changes within a second are told once at once and once at its end", c do
    ContentChanges.touch_environment(c.production)
    assert_receive {:ssg_content_changed, _}

    ContentChanges.touch_environment(c.production)
    ContentChanges.touch_environment(c.production)
    refute_receive {:ssg_content_changed, _}, 500
    assert_receive {:ssg_content_changed, _}, 1_000
    refute_receive {:ssg_content_changed, _}, 1_200
  end

  test "an environment deleted before its mark is written gets none, and nothing raises", c do
    {:ok, _} = Environments.delete_environment(c.staging, actor: :system)

    assert :ok = ContentChanges.touch_environment(c.staging)
    refute marks?()
  end

  describe "changed_since?/1" do
    setup c do
      put_test_env(:ssg_builder, SuccessfulBuilder)
      %{build: build!(c.site, c.production, c.user)}
    end

    test "compares with when the build started", c do
      assert c.build.started_at
      refute ContentChanges.changed_since?(c.build)

      ContentChanges.touch_environment(c.production)
      assert ContentChanges.changed_since?(c.build)
      refute ContentChanges.changed_since?(%{c.build | started_at: DateTime.add(DateTime.utc_now(), 60)})
    end

    test "a build from before started_at was recorded compares with when it was queued", c do
      build = %{c.build | started_at: nil, inserted_at: DateTime.add(DateTime.utc_now(), -60)}
      ContentChanges.touch_environment(c.production)
      assert ContentChanges.changed_since?(build)
    end

    # A mark lost, or an edit before the table had a row
    test "is true for an edit the activity log has since then, with no mark", c do
      log!(c.site, c.production, :tool_called)
      refute ContentChanges.changed_since?(c.build)

      log!(c.site, c.production, :updated)
      refute marks?()
      assert ContentChanges.changed_since?(c.build)
    end

    test "an edit in another environment does not count", c do
      log!(c.site, c.staging, :updated)
      ContentChanges.touch_environment(c.staging)
      refute ContentChanges.changed_since?(c.build)
    end

    # An environment copied over drops and clones its schema again
    test "is true, and raises nothing, while the environment's schema is gone", c do
      Brando.Repo.repo().query!(~s(DROP SCHEMA "#{Tenant.prefix(c.site, c.production)}" CASCADE))
      assert ContentChanges.changed_since?(c.build)
    end

    test "is true when the build's environment is gone", c do
      assert ContentChanges.changed_since?(%{c.build | environment: nil})
    end
  end

  describe "a static build" do
    # Rendering can write (render caches, blocks saved again): what the
    # build's own requests write is no change
    test "writing in its own page requests leaves no change", c do
      page = page!(c.site, c.production, c.user)
      # Through `Brando.Query`, which evicts, and not logged, as a render's write is
      render_saving(fn ->
        Tenant.with_prefix(Tenant.prefix(c.site, c.production), fn ->
          {:ok, _} = page |> Ecto.Changeset.change(title: "Saved") |> Brando.Query.update()
        end)
      end)

      build = build!(c.site, c.production, c.user)

      assert build.status == :ready
      assert title(c.site, c.production, page) == "Saved"
      refute ContentChanges.changed_since?(build)
    end

    test "a save while it builds leaves it changed", c do
      page = page!(c.site, c.production, c.user)
      render_saving(fn -> Task.await(Task.async(fn -> update_page!(c.site, c.production, page, c.user) end)) end)

      build = build!(c.site, c.production, c.user)

      assert build.status == :ready
      assert ContentChanges.changed_since?(build)
    end
  end

  describe "activating an asset set" do
    test "for the site marks each of its environments", c do
      {:ok, set} = register_set(c.site, "site-set")
      assert {:ok, _} = SiteAssets.activate_set(set.id)

      assert ContentChanges.changed_at(c.production)
      assert ContentChanges.changed_at(c.staging)
    end

    test "standalone marks every static site's environments in :single, and none in :multi", c do
      {:ok, set} = register_set(nil, "standalone-set")
      assert {:ok, _} = SiteAssets.activate_set(set.id)
      refute marks?()

      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, c.site.key)
      {:ok, set} = register_set(nil, "single-set")
      assert {:ok, _} = SiteAssets.activate_set(set.id)

      assert ContentChanges.changed_at(c.production)
      assert ContentChanges.changed_at(c.staging)
      refute ContentChanges.changed_at(c.dynamic_production)
    end

    test "for one environment marks that one", c do
      {:ok, set} = register_set(c.site, "staging-set")
      assert {:ok, _} = SiteAssets.activate_environment_set(set.id, c.staging)

      assert ContentChanges.changed_at(c.staging)
      refute ContentChanges.changed_at(c.production)
    end
  end

  describe "copying an environment" do
    test "over another marks the target", c do
      assert {:ok, _} = Environments.copy_environment(c.production, c.staging)

      assert ContentChanges.changed_at(c.staging)
      refute ContentChanges.changed_at(c.production)
    end

    test "or creating one makes no table of marks in its schema", c do
      assert {:ok, _} = Environments.copy_environment(c.production, c.staging)

      {:ok, created} =
        Environments.create_environment(c.site, %{name: "Review", key: "review", live: false}, actor: :system)

      for environment <- [c.production, c.staging, created] do
        refute table?(Tenant.prefix(c.site, environment), "ssg_content_changes")
      end

      assert table?("public", "ssg_content_changes")
      {:ok, tables} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
      refute "ssg_content_changes" in tables
    end
  end

  # Answers the build's page requests as `Brando.Plug.Tenant` does, and
  # calls `save` while it renders
  defp render_saving(save) do
    test = self()

    Brando.Test.SSGEndpoint.start(
      fn request ->
        # The test's configuration (`Brando.Test.ScopedEnv`)
        Process.put(:"$callers", [test])

        header = Brando.SSG.Context.header()
        conn = Plug.Conn.put_req_header(Plug.Test.conn(:get, request.path), header, request.headers[header])

        if Brando.Plug.Tenant.call(conn, []).private[:brando_ssg_build] do
          save.()
          {200, "<main>home</main>"}
        else
          {500, "not a build request"}
        end
      end,
      config: [pubsub_server: Brando.pubsub()]
    )

    put_test_env(:endpoint_module, Brando.Test.SSGEndpoint)
    put_test_env(:ssg_builder, RenderingBuilder)
  end

  defp build!(site, environment, user) do
    {:ok, build} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Builds.request_build(site, environment, creator: user, creator_id: user.id, auto_deploy: false)
      end)

    assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
    Builds.get_build(build.id)
  end

  defp site!(key, delivery_mode) do
    {:ok, site} =
      Registry.create_site(%{
        name: key,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: delivery_mode
      })

    site
  end

  defp environment!(site, key, live) do
    {:ok, environment} =
      Environments.create_environment(site, %{name: key, key: key, live: live, domain: "#{key}.#{site.key}.test"},
        actor: :system
      )

    environment
  end

  defp page!(site, environment, user, attrs \\ []) do
    Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
      :page
      |> Factory.build(Keyword.merge([title: "Page", creator: nil, creator_id: user.id], attrs))
      |> Brando.Repo.insert!()
    end)
  end

  defp update_page!(site, environment, page, user) do
    Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
      {:ok, _} = Brando.Pages.update_page(page.id, %{title: "Saved"}, user)
    end)
  end

  defp title(site, environment, page),
    do: Tenant.with_prefix(Tenant.prefix(site, environment), fn -> Brando.Repo.get!(Page, page.id).title end)

  defp log!(site, environment, action) do
    Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
      Brando.Repo.insert!(%Event{action: action, source: :admin, schema: "Elixir.Brando.Pages.Page", entry_id: 1})
    end)
  end

  defp register_set(site, name) do
    path = Brando.SiteAssetsFixtures.create_set(site, name, "console.log(1)", "#{name}.css")
    SiteAssets.register_set(site, path, %{})
  end

  defp marks?,
    do: Brando.Repo.all(from(change in "ssg_content_changes", select: change.environment_id), prefix: "public") != []

  defp table?(schema, table) do
    %{rows: [[name]]} = Brando.Repo.repo().query!("SELECT to_regclass($1)::text", [~s("#{schema}".#{table})])
    not is_nil(name)
  end

  # A session of the test database outside the test's sandbox: what it
  # writes others see once it has committed
  defp own_session do
    start_supervised!({BrandoIntegration.Repo, name: nil, pool: DBConnection.ConnectionPool, pool_size: 2})
  end

  defp in_session(session, fun) do
    Task.async(fn ->
      BrandoIntegration.Repo.put_dynamic_repo(session)
      fun.()
    end)
  end

  # A session of this database waits for an advisory lock
  defp waiter_waiting?(session, tries \\ 40) do
    %{rows: [[waiting]]} =
      session
      |> in_session(fn ->
        Brando.Repo.repo().query!("""
        SELECT count(*) FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        """)
      end)
      |> Task.await()

    cond do
      waiting > 0 ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(50)
        waiter_waiting?(session, tries - 1)
    end
  end

  # What `at_mark` returns at each statement that writes a mark while `fun`
  # runs, in the process that writes it
  defp at_marks(at_mark, fun) do
    test = self()
    handler = "content-changes-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if query =~ "INSERT INTO public.ssg_content_changes", do: send(test, {:at_mark, at_mark.()})
      end,
      nil
    )

    try do
      result = fun.()
      {received_at_marks([]), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp received_at_marks(values) do
    receive do
      {:at_mark, value} -> received_at_marks([value | values])
    after
      0 -> Enum.reverse(values)
    end
  end

  # How many statements wrote a mark while `fun` ran
  defp counting_marks(fun) do
    {marks, result} = at_marks(fn -> :marked end, fun)
    {length(marks), result}
  end
end
