defmodule Brando.Content.Proposals.PreviewTranslationLinkTest do
  # A link to the page of a translation a proposal creates, as the tool's
  # `preview_proposal` and the admin's share link make it: the page renders
  # in a process of its own while the caller holds the site's asset lock on
  # its connection, which needs two connections at once. So outside the
  # sandbox, on committed rows (`Brando.Test.Committed`). A barrier holds the
  # renderer at its first render query, after the copy is made.
  use ExUnit.Case, async: false

  # A renderer stopped at its deadline takes its connection down, which the
  # pool logs
  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Retention
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Preview
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Repo
  alias Brando.Test.SiteRouter, as: Router
  alias Brando.Test.Support
  alias Brando.Translations

  @handler __MODULE__

  setup_all do
    Brando.Test.Committed.template()
  end

  setup tags do
    :ok = Brando.Test.Committed.start(tags.template)
    root = Path.join(System.tmp_dir!(), "brando-preview-link-#{System.unique_integer([:positive])}")
    release = Path.join(root, "release")
    write_release(release, "aaaa")
    Support.put_test_env(:release_static_path, release)
    Support.put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    Support.put_test_env(Page, translatable: [mode: :synchronized])
    SiteAssets.invalidate_cache()

    on_exit(fn ->
      :telemetry.detach(@handler)
      SiteAssets.invalidate_cache()
      File.rm_rf(root)
    end)

    c = ProposalFixtures.context()
    Map.merge(c, ProposalFixtures.card_pages(c.user, other_en: Map.get(tags, :other_en, false)))
  end

  defp mcp(c), do: %Context{actor: c.user, origin: :mcp, client: "Claude Code"}

  defp page(page), do: %{"content_type" => "Brando.Pages.Page", "id" => page.id}

  defp create_op(source, ref \\ "english"),
    do: %{"op" => "create_translation", "source" => page(source), "language" => "en", "ref" => ref}

  defp translate_new(c) do
    {:ok, %{units: units}} = Translations.Work.new_translation_units(Page, c.source.id)
    scope = %{type: to_string(Page), id: {:new, c.source.id}, language: "en"}
    ProposalFixtures.translate_kicker(units, scope, %{"new" => "english"}, c.kicker)
  end

  defp prepare!(c, operations) do
    assert {:ok, %{proposal_id: id} = review} =
             Tools.call("prepare_proposal", %{"summary" => "Translate", "operations" => operations}, mcp(c))

    assert review.problems == [], inspect(review.problems)
    {:ok, proposal} = Proposals.get(id, c.user)
    proposal
  end

  # The link, by the tool or by the admin's review
  defp link(c, proposal, target, via, preview_target \\ "blocks")

  defp link(c, proposal, target, :tool, preview_target) do
    args = %{"proposal_id" => proposal.id, "target" => target, "preview_target" => preview_target}

    with {:ok, %{url: url}} <- Tools.call("preview_proposal", args, mcp(c)), do: {:ok, url}
  end

  defp link(c, proposal, %{"new" => ref}, :admin, preview_target) do
    target = String.to_existing_atom(preview_target)

    with {:ok, url, _days} <- Preview.share(proposal, {:new, ref}, c.user, preview_target: target), do: {:ok, url}
  end

  # The link as a browser opens it: through a site's router, with no login
  defp open(url) do
    :get
    |> Plug.Test.conn("https://admin.test#{URI.parse(url).path}")
    |> Map.put(:host, "admin.test")
    |> Router.call(Router.init([]))
  end

  # Every row a preview could leave behind, but the snapshot and its purger
  defp kept do
    schemas = [
      Page,
      Page.Alternate,
      Brando.Content.Block,
      Brando.Content.Var,
      Brando.Content.Identifier,
      Brando.Translations.Group,
      Brando.Translations.Member,
      Brando.Translations.PendingVersion,
      Brando.Translations.WorkItem,
      Brando.Activity.Event
    ]

    jobs = Repo.aggregate(from(j in Oban.Job, where: j.worker != "Brando.Worker.PreviewPurger"), :count)
    schemas |> Map.new(&{&1, Repo.aggregate(&1, :count)}) |> Map.put(Oban.Job, jobs)
  end

  defp snapshots, do: {Repo.aggregate(Brando.Sites.Preview, :count), purgers()}

  defp purgers,
    do: Repo.aggregate(from(j in Oban.Job, where: j.worker == "Brando.Worker.PreviewPurger"), :count)

  # The repo's timeout, which a preview's render has
  defp put_deadline(ms) do
    repo = Repo.repo()
    config = Application.fetch_env!(:brando, repo)
    Support.put_test_env(repo, Keyword.put(config, :timeout, ms))
  end

  # The renderer stops at its first query on `source` (`lock: true`, a row
  # lock) and tells the test what it holds, until the test lets it go on
  defp close_barrier(source, opts \\ []) do
    table = :ets.new(@handler, [:public])
    config = %{test: self(), table: table, source: source, lock: Keyword.get(opts, :lock, false)}

    :ok =
      :telemetry.attach(
        @handler,
        Repo.repo().config()[:telemetry_prefix] ++ [:query],
        &__MODULE__.barrier/4,
        config
      )
  end

  @doc false
  def barrier(_event, _measurements, %{source: source, query: query}, config) do
    if source == config.source and (not config.lock or query =~ "FOR UPDATE") and
         config.test in (Process.get(:"$callers") || []) and :ets.insert_new(config.table, {:paused}) do
      held = %{override: SiteAssets.override(), scope: Brando.Authorization.Boundary.current_scope()}

      send(config.test, {:paused, self(), held})

      receive do
        :release -> :ok
      after
        10_000 -> :ok
      end
    end

    :ok
  end

  # Whether another session can take the lock now, waiting a second at most
  defp lock_free?(fun) do
    task =
      Task.async(fn ->
        Repo.transaction(fn ->
          Ecto.Adapters.SQL.query!(Repo.repo(), "SET LOCAL lock_timeout = '1s'")
          fun.()
        end)
      end)

    match?({:ok, _}, Task.await(task, 5_000))
  rescue
    _ in Postgrex.Error -> false
  end

  defp row_lock_free?(schema, id),
    do: lock_free?(fn -> Repo.one(from(r in schema, where: r.id == ^id, select: r.id, lock: "FOR UPDATE")) end)

  for via <- [:tool, :admin] do
    test "a #{via} link whose render outlasts its deadline answers then, with every lock free", c do
      {:ok, member} = Translations.enroll_source(Page, c.source.id, c.user)
      proposal = prepare!(c, [create_op(c.source), translate_new(c)])
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      put_deadline(1_000)

      # Held at the barrier: the answer comes at the deadline, and the
      # renderer's connection went with it
      close_barrier("content_palettes")
      started = System.monotonic_time(:millisecond)
      assert {:error, message} = link(c, proposal, %{"new" => "english"}, unquote(via))
      assert message =~ "took too long"
      assert System.monotonic_time(:millisecond) - started < 5_000
      assert_received {:paused, renderer, _held}
      refute Process.alive?(renderer)

      assert row_lock_free?(Page, c.source.id)
      assert row_lock_free?(Translations.Group, member.group_id)
      refute Brando.Tenant.Lock.held?(SiteAssets.lock_key(nil))

      # An apply that waited on the copy's source goes through once it is stopped
      :telemetry.detach(@handler)
      close_barrier("content_palettes")
      preview = Task.async(fn -> link(c, proposal, %{"new" => "english"}, unquote(via)) end)
      assert_receive {:paused, _renderer, _held}, 5_000
      apply = Task.async(fn -> Proposals.apply(proposal.id, proposal.version, c.user) end)
      refute Task.yield(apply, 300)

      assert {:error, _message} = Task.await(preview, 5_000)
      assert {:ok, %Proposals.Receipt{}} = Task.await(apply, 10_000)
    end
  end

  # A proposal that creates two translations: the copy whose link is opened
  # and the sibling its card links
  defp sibling_proposal(c) do
    {:ok, %{units: units}} = Translations.Work.new_translation_units(Page, c.other.id)
    units = Enum.filter(units, &(&1.answerable and &1.key == "title"))
    scope = %{type: to_string(Page), id: {:new, c.other.id}, language: "en"}

    title = %{
      "op" => "translate",
      "target" => %{"new" => "project"},
      "source_digest" => Translations.Work.token(scope, units),
      "texts" => %{"title" => "Project"}
    }

    prepare!(c, [create_op(c.other, "project"), title, create_op(c.source)])
  end

  describe "a translation the proposal creates, its card's project translated" do
    @describetag other_en: true

    test "shows the copy with the proposal's texts and its links, keeping nothing", c do
      proposal = prepare!(c, [create_op(c.source), translate_new(c)])

      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(Page)}"))
      before = kept()
      # The render reads the card's module through the query cache, which
      # would keep it
      Support.preserve_query_cache(Brando.Content.Module)
      Brando.Cache.Query.evict_schema(Brando.Content.Module)
      cached = Cachex.size!(:query)

      assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool)
      body = open(url).resp_body
      assert body =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert body =~ ~s(<a class="card">Project</a>)
      refute body =~ "Våre prosjekter"
      refute body =~ "Prosjekt"

      assert kept() == before
      assert Cachex.size!(:query) == cached
      # Broadcasts are held for a commit, which the rollback never makes
      refute_received {:mutation, _, _, _}
      assert Translations.get_member(Page, c.source.id) == nil
    end

    # The listing's assigns hold the copy's id and title, gone once rolled back
    test "keeps none of the view's assigns", c do
      proposal = prepare!(c, [create_op(c.source), translate_new(c)])

      assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool, "listing")
      assert open(url).resp_body =~ "Om oss"

      {:ok, keys} = Cachex.keys(:cache)

      assert for(
               key <- keys,
               is_binary(key) and key =~ "__VAR__employees",
               match?({:ok, [%{name: "Om oss"}]}, Cachex.get(:cache, key)),
               do: key
             ) == []
    end

    test "shows the untranslated copy without a translate", c do
      proposal = prepare!(c, [create_op(c.source)])
      before = kept()

      assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool)
      body = open(url).resp_body
      assert body =~ ~s(<h2 class="kicker">Våre prosjekter</h2>)
      assert body =~ ~s(<a class="card">Project</a>)

      assert kept() == before
    end

    # The admin's review renders the same page into its frame, and shares it
    test "shows the review's page preview and shareable link, keeping nothing", c do
      proposal = prepare!(c, [create_op(c.source), translate_new(c)])
      assert Proposals.Review.preview_key(proposal) == "new:english"
      before = kept()

      assert {:ok, %{key: key, html: html}} = Preview.render(proposal, {:new, "english"}, c.user, preview_target: :blocks)
      assert html =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert html =~ ~s(<a class="card">Project</a>)
      # The frame opens for its editor, though the copy is gone
      assert Brando.Authorization.Preview.authorize(key, c.user.id) == :ok
      Preview.discard([key])

      assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :admin)
      assert open(url).resp_body =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert kept() == before
    end
  end

  # The page's card links the project, which the same proposal translates
  # too: the preview has the project's English version, as applying makes it
  test "links the proposal's other translation", c do
    proposal = sibling_proposal(c)
    before = kept()

    assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool)
    body = open(url).resp_body
    assert body =~ ~s(<a class="card">Project</a>)
    refute body =~ "Prosjekt"
    assert kept() == before
    assert Translations.get_member(Page, c.other.id) == nil
  end

  test "a render stopped at its deadline keeps nothing and stores nothing later; the retry stores once", c do
    proposal = sibling_proposal(c)

    Oban.Testing.with_testing_mode(:manual, fn ->
      before = kept()
      {snapshots, purgers} = snapshots()
      put_deadline(1_000)
      close_barrier("content_palettes")

      assert {:error, message} = link(c, proposal, %{"new" => "english"}, :tool)
      assert message =~ "took too long"
      assert_received {:paused, renderer, _held}
      send(renderer, :release)
      refute Process.alive?(renderer)
      assert kept() == before
      assert snapshots() == {snapshots, purgers}
      assert Translations.get_member(Page, c.other.id) == nil

      :telemetry.detach(@handler)
      put_deadline(15_000)
      assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool)
      assert open(url).resp_body =~ ~s(<a class="card">Project</a>)
      assert snapshots() == {snapshots + 1, purgers + 1}
    end)
  end

  test "the render reads the asset set the caller pinned, in the actor's scope", c do
    proposal = prepare!(c, [create_op(c.source)])
    close_barrier("content_palettes")
    preview = Task.async(fn -> link(c, proposal, %{"new" => "english"}, :tool) end)
    assert_receive {:paused, renderer, held}, 5_000

    # Activated while the page renders: the snapshot keeps the pinned set
    next_path = Brando.SiteAssetsFixtures.create_set(nil, "next-build", "js-next", "next.css")
    {:ok, next} = SiteAssets.register_set(next_path)
    send(renderer, :release)

    assert {:ok, url} = Task.await(preview, 15_000)
    {:ok, _} = SiteAssets.activate_set(next.id)
    stored = Repo.one!(from(p in Brando.Sites.Preview, order_by: [desc: p.id], limit: 1))
    assert held.override.set.id == stored.asset_set_id
    assert held.scope.user_id == c.user.id
    assert open(url).status == 200
  end

  test "a link that succeeded still opens after another set is activated and the old pruned", c do
    proposal = prepare!(c, [create_op(c.source), translate_new(c)])
    assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool)

    next_path = Brando.SiteAssetsFixtures.create_set(nil, "next-build", "js-next", "next.css")
    {:ok, next} = SiteAssets.register_set(next_path)
    {:ok, _} = SiteAssets.activate_set(next.id)
    {:ok, _} = Retention.prune_captured_sets()
    {:ok, _} = Retention.prune_sets(keep: 1)

    response = open(url)
    assert response.status == 200
    assert response.resp_body =~ ~s(<h2 class="kicker">Our projects</h2>)
  end

  # A preview locks the sources it makes translations of first, sorted, as
  # the apply locks them: an apply of another proposal that locks the same
  # two pages waits for it, rather than meeting it in the opposite order
  test "a preview and an apply that lock the same sources do not deadlock", c do
    # `source` was made first: the apply locks it first
    assert c.source.id < c.other.id
    {:ok, %{units: units}} = Translations.Work.new_translation_units(Page, c.other.id)
    units = Enum.filter(units, &(&1.answerable and &1.key == "title"))
    scope = %{type: to_string(Page), id: {:new, c.other.id}, language: "en"}

    title = %{
      "op" => "translate",
      "target" => %{"new" => "project"},
      "source_digest" => Translations.Work.token(scope, units),
      "texts" => %{"title" => "Project"}
    }

    # The copy of `source`, made first, takes no translate
    preview_proposal = prepare!(c, [create_op(c.source), create_op(c.other, "project"), title])

    retitle =
      prepare!(c, [
        %{"op" => "set_fields", "target" => page(c.source), "fields" => %{"title" => "Om oss igjen"}},
        %{"op" => "set_fields", "target" => page(c.other), "fields" => %{"title" => "Prosjekt igjen"}}
      ])

    {:ok, _} = Proposals.approve(retitle.id, retitle.version, c.user)

    # The preview stops once it holds its first source
    close_barrier("pages", lock: true)
    preview = Task.async(fn -> link(c, preview_proposal, %{"new" => "project"}, :tool) end)
    assert_receive {:paused, renderer, _held}, 5_000

    apply = Task.async(fn -> Proposals.apply(retitle.id, retitle.version, c.user) end)
    # The apply waits on a source the preview holds
    refute Task.yield(apply, 500)
    send(renderer, :release)

    assert {:ok, url} = Task.await(preview, 15_000)
    assert open(url).resp_body =~ "Project"
    assert {:ok, %Proposals.Receipt{}} = Task.await(apply, 15_000)
  end

  describe "a translation the proposal creates, in one environment of one of several sites" do
    alias Brando.Tenant
    alias Brando.Tenant.Registry

    # Both sites' schemas hold the same rows, so the same ids: each page's
    # text tells whose it is. Each site has an asset set of its own.
    setup do
      Support.put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()

      alpha = site("Link Alpha", "link-alpha")
      beta = site("Link Beta", "link-beta")
      alpha_live = environment(alpha, "production")
      beta_live = environment(beta, "production")
      beta_staging = environment(beta, "staging")

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Tenant.Cache.clear()
      end)

      for {environment, site, kicker} <- [
            {alpha_live, alpha, "Alfas prosjekter"},
            {beta_staging, beta, "Betas prosjekter"}
          ] do
        Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
          Repo.update_all(from(v in Brando.Content.Var, where: v.key == "kicker"), set: [value: kicker])
        end)
      end

      sets = Map.new([alpha, beta], &{&1.key, active_set(&1)})
      %{prefix: Tenant.prefix(beta, beta_staging), beta_staging: beta_staging, beta: beta, sets: sets}
    end

    defp site(name, key) do
      {:ok, site} =
        Registry.create_site(%{
          name: name,
          key: key,
          languages: ["no", "en"],
          default_language: "no",
          status: :active,
          delivery_mode: :dynamic
        })

      site
    end

    # The environment's schema, a copy of `public`'s tables and rows
    defp environment(site, key) do
      {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
      prefix = Tenant.prefix(site, environment)
      sql!(~s(CREATE SCHEMA "#{prefix}"))

      for [table] <- sql!("SELECT tablename FROM pg_tables WHERE schemaname = 'public'").rows,
          not Tenant.SharedTables.member?(table) do
        sql!(~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
        sql!(~s|INSERT INTO "#{prefix}"."#{table}" SELECT * FROM public."#{table}"|)
      end

      environment
    end

    defp sql!(query), do: Ecto.Adapters.SQL.query!(Repo.repo(), query)

    defp active_set(site) do
      path = Brando.SiteAssetsFixtures.create_set(site, site.key, "js-#{site.key}", "#{site.key}.css")
      {:ok, set} = SiteAssets.register_set(site, path, %{})
      {:ok, set} = SiteAssets.activate_set(set.id)
      set
    end

    # The snapshot is stored for the site and environment it was shared
    # from, with that site's copy and asset set
    for via <- [:tool, :admin] do
      test "the #{via} link stores the copy made in that site's environment, with its asset set", c do
        Tenant.with_prefix(c.prefix, fn ->
          proposal = prepare!(c, [create_op(c.source)])
          assert {:ok, _url} = link(c, proposal, %{"new" => "english"}, unquote(via))
        end)

        stored = Repo.one!(from(p in Brando.Sites.Preview, order_by: [desc: p.id], limit: 1))
        assert stored.site_id == c.beta.id
        assert stored.environment_id == c.beta_staging.id
        assert stored.asset_set_id == c.sets[c.beta.key].id

        html = Brando.Utils.binary_to_term(stored.html)
        assert html =~ ~s(<h2 class="kicker">Betas prosjekter</h2>)
        refute html =~ "Alfas prosjekter"
        refute html =~ "Våre prosjekter"
      end
    end
  end

  describe "shared by one who may create pages but not export them" do
    alias Brando.Authorization.Catalog, as: Grants
    alias Brando.Authorization.Groups
    alias Brando.Authorization.Scope

    setup c do
      Support.put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      Repo.update_all(from(p in Page, where: p.id == ^c.source.id), set: [status: :draft])

      editor = Brando.Factory.insert(:random_user, role: :user)

      grants =
        Enum.map([:read, :create, :update, :duplicate], &Grants.get(&1, Page).key) ++
          [Grants.get(:read, Brando.Content.Module).key, "brando.admin.access"]

      {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Page editors"}, grants)
      {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, editor.id)
      refute Brando.Authorization.Engine.can?(Scope.standalone(editor), :export, Page)

      %{editor: editor}
    end

    # The tool's link takes no export permission; the admin's does
    test "gets the tool's link, and is refused the admin's", c do
      c = %{c | user: c.editor}
      proposal = prepare!(c, [create_op(c.source)])

      assert {:ok, url} = link(c, proposal, %{"new" => "english"}, :tool)
      assert open(url).resp_body =~ ~s(<h2 class="kicker">Våre prosjekter</h2>)
      assert {:error, :forbidden} = link(c, proposal, %{"new" => "english"}, :admin)
    end
  end

  # What the release ships, as `Brando.Assets.PreviewPinningTest` writes it
  defp write_release(release, digest) do
    File.mkdir_p!(Path.join(release, "assets"))
    File.write!(Path.join(release, "assets/main-#{digest}.js"), "js-#{digest}")
    File.write!(Path.join(release, "assets/main-#{digest}.css"), "css-#{digest}")

    manifest = %{
      "js/index.js" => %{"isEntry" => true, "file" => "assets/main-#{digest}.js", "css" => ["assets/main-#{digest}.css"]}
    }

    File.write!(Path.join(release, "manifest.json"), Jason.encode!(manifest))
  end
end
