defmodule Brando.Setup.RemoveDefaultsTest do
  # `Brando.Setup.Seeds.remove_defaults/1` and `mix brando.seeds.remove_defaults`:
  # what still uses the seeds' modules, and taking away what nothing uses
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureIO, only: [capture_io: 1]

  alias Brando.Content
  alias Brando.Factory
  alias Brando.Navigation
  alias Brando.Pages
  alias Brando.Repo
  alias Brando.Setup.Seeds

  @page_modules ~w(hero steps cards tips terminal closing)

  # The seeds and the removal refill the identity, SEO and navigation caches
  # from this test's sandboxed rows, which roll back
  setup do
    cached = Map.new(~w(identity seo navigation)a, &{&1, Brando.Cache.get(&1)})

    on_exit(fn ->
      Enum.each(cached, fn
        {key, nil} -> Brando.Cache.del(key)
        {key, value} -> Brando.Cache.put(key, value, :infinite)
      end)
    end)

    %{user: Factory.insert(:random_user)}
  end

  describe "a dry run" do
    test "lists each seeded module and what uses it, and changes nothing", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en, :no])
      about = page_using!(user, "about", "About us", :no, ["hero"])
      before = snapshot()

      {{:ok, [report]}, output} = remove([])

      assert snapshot() == before

      statuses = Map.new(report.modules, &{&1.module.uid, &1.status})
      assert statuses["brando-default-hero"] == :in_use
      for name <- @page_modules -- ["hero"], do: assert(statuses["brando-default-#{name}"] == :removable)
      assert statuses["brando-default-footer"] == :removable

      hero = Enum.find(report.modules, &(&1.module.uid == "brando-default-hero"))
      assert [%{label: "About us", language: :no, blocks: 1, trashed: false} = user_entry] = hero.users
      assert user_entry.url =~ "/admin/pages/update/#{about.id}"

      assert report.entries |> Enum.map(&{&1.type, &1.language, &1.status}) |> Enum.sort() ==
               Enum.sort(for l <- [:en, :no], t <- ["page", "fragment"], do: {t, l, :removable})

      assert output =~ "brando-default-hero"
      assert output =~ ~s["About us" (no)]
      assert output =~ "/admin/pages/update/#{about.id}"
      assert output =~ "still used"
      assert output =~ "Dry run: nothing was changed"
      assert output =~ "--yes"
    end

    test "says there is nothing to remove after seeding without the demo", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en], demo: false)

      {{:ok, [report]}, output} = remove([])

      assert report.modules == []
      assert report.entries == []
      assert output =~ "No modules from the seeds"
    end
  end

  describe "with yes: true" do
    test "moves the unused modules, and the homepage and footer as seeded, to the trash", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en, :no])
      about = page_using!(user, "about", "About", :en, ["hero"])
      rendered = Repo.get!(Pages.Page, about.id).rendered_blocks

      {{:ok, [report]}, output} = remove(yes: true)

      assert live_modules() == ["brando-default-hero"]
      refute Enum.any?(live_pages(), &(&1.uri == "index"))
      assert live_footers() == []

      # What the seeds made that is not the demo stays
      assert Repo.get_by(Navigation.Menu, key: "main", language: :en)
      assert {:ok, _} = Brando.Sites.get_identity(%{matches: %{language: :en}})

      # The page that uses the module is left as it was
      assert Repo.get!(Pages.Page, about.id).rendered_blocks == rendered
      assert Repo.get!(Pages.Page, about.id).deleted_at == nil

      assert Enum.find(report.modules, &(&1.module.uid == "brando-default-steps")).status == :removed
      assert Enum.find(report.modules, &(&1.module.uid == "brando-default-hero")).status == :in_use
      assert Enum.all?(report.entries, &(&1.status == :removed))

      assert output =~ "moved to the trash"
      assert output =~ ~s["About" (en)]
      refute output =~ "Dry run"
    end

    test "a run again finds nothing more, and the seeds bring nothing back", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])
      {{:ok, _}, _} = remove(yes: true)
      before = snapshot()

      {{:ok, [report]}, output} = remove(yes: true)
      assert report.modules == []
      assert report.entries == []
      assert output =~ "No modules from the seeds"

      {:ok, rerun} = Seeds.run(user, languages: [:en])
      assert rerun.created == []
      assert snapshot() == before
      assert live_modules() == []
    end

    test "a language seeded after the removal gets a homepage without the trashed modules", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])
      {{:ok, _}, _} = remove(yes: true)

      {:ok, report} = Seeds.run(user, languages: [:no])

      assert :"page (no)" in report.created
      assert live_modules() == []
      page = Pages.Page |> Repo.get_by!(uri: "index", language: :no) |> Repo.preload(:entry_blocks)
      assert page.entry_blocks == []
    end

    test "keeps a module used by an entry in the trash, and says so", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])
      about = page_using!(user, "about", "About", :en, ["tips"])
      {:ok, _} = Repo.soft_delete(Repo.get!(Pages.Page, about.id))

      {{:ok, [report]}, output} = remove(yes: true)

      assert live_modules() == ["brando-default-tips"]
      tips = Enum.find(report.modules, &(&1.module.uid == "brando-default-tips"))
      assert [%{trashed: true}] = tips.users
      assert output =~ "in the trash"
    end

    test "keeps the homepage while a fragment of its own is on it", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])
      page = Repo.get_by!(Pages.Page, uri: "index", language: :en)
      Factory.insert(:fragment, parent_key: "index", key: "intro", language: :en, page_id: page.id)

      {{:ok, [report]}, output} = remove(yes: true)

      assert Repo.get!(Pages.Page, page.id).deleted_at == nil
      assert live_footers() == []
      assert live_modules() == Enum.map(@page_modules, &"brando-default-#{&1}") |> Enum.sort()
      assert %{status: :kept} = Enum.find(report.entries, &(&1.type == "page"))
      assert output =~ "fragments"
    end
  end

  describe "content changed since it was seeded" do
    edits = [
      {"a ref's text", :ref_text},
      {"the page's title", :title},
      {"a block taken out", :block_removed},
      {"the page unpublished", :unpublished},
      {"a block hidden", :block_hidden}
    ]

    for {label, edit} <- edits do
      test "is kept, with the modules it uses: #{label}", %{user: user} do
        {:ok, _} = Seeds.run(user, languages: [:en, :no])
        page = Repo.get_by!(Pages.Page, uri: "index", language: :en)
        edit!(unquote(edit), page)

        {{:ok, [report]}, output} = remove(yes: true)

        assert Repo.get!(Pages.Page, page.id).deleted_at == nil
        refute Enum.any?(live_pages(), &(&1.uri == "index" and &1.language == :no))

        # The footers are as seeded, so they go, and their module with them
        assert live_footers() == []
        refute "brando-default-footer" in live_modules()

        # The page's modules stay while it uses them
        assert "brando-default-cards" in live_modules()

        assert %{status: :kept} = Enum.find(report.entries, &(&1.type == "page" and &1.language == :en))
        assert output =~ "changed since it was seeded"
      end
    end

    test "a footer an editor changed is kept, with its module, and the homepage it is on", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en, :no])
      footer = Repo.get_by!(Pages.Fragment, parent_key: "partials", key: "footer", language: :en)
      footer |> Ecto.Changeset.change(title: "Our footer") |> Repo.update!()

      {{:ok, [report]}, output} = remove(yes: true)

      assert Repo.get!(Pages.Fragment, footer.id).deleted_at == nil
      assert Repo.get!(Pages.Page, footer.page_id).deleted_at == nil
      assert [%{language: :en}] = live_footers()
      assert "brando-default-footer" in live_modules()

      assert %{status: :kept} = Enum.find(report.entries, &(&1.type == "fragment" and &1.language == :en))
      assert %{status: :kept} = Enum.find(report.entries, &(&1.type == "page" and &1.language == :en))
      assert %{status: :removed} = Enum.find(report.entries, &(&1.type == "page" and &1.language == :no))
      assert output =~ "fragments are on it (Our footer (en))"
    end
  end

  describe "options" do
    test "the release function prints to standard output by default", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])

      output = capture_io(fn -> assert {:ok, [_report]} = Seeds.remove_defaults(yes: true) end)

      assert output =~ "brando-default-hero"
      assert output =~ "moved to the trash"
      assert live_modules() == []
    end

    test "are checked before anything is done", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])
      before = snapshot()

      assert {:error, message} = Seeds.remove_defaults(yes: true, everything: true, info: fn _ -> :ok end)
      assert message =~ "unknown option everything:"

      assert {:error, message} = Seeds.remove_defaults(yes: "please", info: fn _ -> :ok end)
      assert message =~ "yes:"

      assert {:error, message} = Seeds.remove_defaults(yes: true, site: "acme", info: fn _ -> :ok end)
      assert message =~ "need tenancy"

      assert snapshot() == before
    end

    test "mix brando.seeds.remove_defaults lists, and removes with --yes", %{user: user} do
      {:ok, _} = Seeds.run(user, languages: [:en])
      shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      on_exit(fn ->
        Mix.shell(shell)
        Mix.Task.reenable("brando.seeds.remove_defaults")
      end)

      Mix.Tasks.Brando.Seeds.RemoveDefaults.run([])
      assert shell_output() =~ "Dry run: nothing was changed"
      assert length(live_modules()) == 7

      Mix.Tasks.Brando.Seeds.RemoveDefaults.run(["--yes"])
      output = shell_output()
      assert output =~ "moved to the trash"
      assert output =~ "Restart"
      assert live_modules() == []
    end
  end

  describe "with tenancy" do
    @prefixes ~w(tenant_acme_production tenant_acme_staging tenant_beta_production tenant_beta_staging)

    defmodule Migrator do
      @behaviour Brando.Environments.Migrator

      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    setup do
      root = Path.join(System.tmp_dir!(), "brando-remove-defaults-#{System.unique_integer([:positive])}")

      put_test_env(:tenancy_mode, :multi)
      put_test_env(:media_path, Path.join(root, "media"))
      put_test_env(:sites_path, Path.join(root, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()

      on_exit(fn ->
        File.rm_rf(root)
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
        Brando.TenantCaches.clear(@prefixes)
      end)

      creator = Factory.insert(:random_user, role: :superuser, avatar: nil)

      for key <- ~w(acme beta) do
        {:ok, _site} = Brando.Tenant.Setup.create_site(site_attrs(key), creator, environments: environments(key))
      end

      :ok
    end

    test "a dry run lists each environment's modules apart" do
      {{:ok, reports}, output} = remove([])

      assert reports |> Enum.map(&{&1.site, &1.environment}) |> Enum.sort() ==
               Enum.sort(for s <- ~w(acme beta), e <- ~w(production staging), do: {s, e})

      for report <- reports, do: assert(length(report.modules) == 7)
      assert output =~ "Acme (acme) → Staging (staging)"

      for prefix <- @prefixes, do: assert(in_prefix(prefix, &live_modules/0) |> length() == 7)
    end

    test "removes in one site's one environment only" do
      in_prefix("tenant_acme_production", fn ->
        page_using!(Repo.one!(from(u in Brando.Users.User, limit: 1)), "about", "About", :en, ["closing"])
      end)

      {{:ok, [report]}, _output} = remove(yes: true, site: "acme", environment: "staging")

      assert {report.site, report.environment} == {"acme", "staging"}
      assert in_prefix("tenant_acme_staging", &live_modules/0) == []
      assert in_prefix("tenant_acme_staging", &live_footers/0) == []

      for prefix <- @prefixes -- ["tenant_acme_staging"] do
        assert length(in_prefix(prefix, &live_modules/0)) == 7, prefix
        assert in_prefix(prefix, fn -> Enum.any?(live_pages(), &(&1.uri == "index")) end), prefix
      end
    end

    test "names a site or environment that does not exist" do
      assert {{:error, message}, _} = remove(site: "nope")
      assert message =~ ~s(no site has the key "nope")

      assert {{:error, message}, _} = remove(site: "acme", environment: "nope")
      assert message =~ "no environment matches"
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp remove(opts) do
    parent = self()
    info = fn line -> send(parent, {:info, line |> IO.ANSI.format(false) |> IO.iodata_to_binary()}) end
    result = Seeds.remove_defaults(Keyword.put(opts, :info, info))
    {result, collect_info()}
  end

  defp collect_info(output \\ "") do
    receive do
      {:info, line} -> collect_info(output <> line <> "\n")
    after
      0 -> output
    end
  end

  defp shell_output(output \\ "") do
    receive do
      {:mix_shell, kind, [message]} when kind in [:info, :error] -> shell_output(output <> message <> "\n")
    after
      0 -> output
    end
  end

  defp live_modules do
    Repo.all(
      from(m in Content.Module,
        where: like(m.uid, "brando-default-%") and is_nil(m.deleted_at),
        select: m.uid,
        order_by: m.uid
      )
    )
  end

  defp live_pages, do: Repo.all(from(p in Pages.Page, where: is_nil(p.deleted_at)))

  defp live_footers,
    do:
      Repo.all(
        from(f in Pages.Fragment, where: f.parent_key == "partials" and f.key == "footer" and is_nil(f.deleted_at))
      )

  defp snapshot do
    Enum.map([Content.Module, Pages.Page, Pages.Fragment, Content.Block, Navigation.Menu], fn schema ->
      Repo.all(from(e in schema, select: {e.id, field(e, ^deleted_or_updated(schema))}, order_by: e.id))
    end)
  end

  defp deleted_or_updated(schema), do: if(:deleted_at in schema.__schema__(:fields), do: :deleted_at, else: :updated_at)

  # A page of an editor's, holding a block of each named seeded module
  defp page_using!(user, uri, title, language, names) do
    modules = Map.new(Repo.all(Content.Module), &{&1.uid, &1})

    blocks =
      names
      |> Enum.with_index()
      |> Enum.map(fn {name, sequence} ->
        module = Map.fetch!(modules, "brando-default-#{name}")

        %Pages.Page.Blocks{
          sequence: sequence,
          block: %Content.Block{
            type: :module,
            uid: Brando.Utils.generate_uid(),
            module_id: module.id,
            module_version: module.version,
            source: Pages.Page.Blocks,
            sequence: sequence,
            vars: [],
            refs: []
          }
        }
      end)

    page =
      Repo.insert!(%Pages.Page{
        creator_id: user.id,
        title: title,
        uri: uri,
        language: language,
        template: "default.html",
        status: :published,
        entry_blocks: blocks
      })

    {:ok, page} = Content.Blocks.render_entry(Pages.Page, page.id)
    page
  end

  defp edit!(:ref_text, page) do
    [block_id | _] = block_ids(page)
    text = Jason.encode!("<p>Our own lead.</p>")

    {1, _} =
      Repo.update_all(
        from(r in Content.Ref,
          where: r.block_id == ^block_id and r.name == "lead",
          update: [set: [data: fragment("jsonb_set(?, '{data,text}', ?::jsonb)", r.data, ^text)]]
        ),
        []
      )
  end

  defp edit!(:title, page), do: page |> Ecto.Changeset.change(title: "Home") |> Repo.update!()
  defp edit!(:unpublished, page), do: page |> Ecto.Changeset.change(status: :draft) |> Repo.update!()

  defp edit!(:block_removed, page) do
    last = List.last(block_ids(page))
    Repo.delete_all(from(j in Pages.Page.Blocks, where: j.entry_id == ^page.id and j.block_id == ^last))
  end

  defp edit!(:block_hidden, page) do
    [first | _] = block_ids(page)
    Repo.update_all(from(b in Content.Block, where: b.id == ^first), set: [active: false])
  end

  defp block_ids(page) do
    Repo.all(from(j in Pages.Page.Blocks, where: j.entry_id == ^page.id, order_by: j.sequence, select: j.block_id))
  end

  defp in_prefix(prefix, fun), do: Brando.Tenant.with_prefix(prefix, fun)

  defp environments(key) do
    [
      %{name: "Production", key: "production", live: true, domain: "#{key}.test"},
      %{name: "Staging", key: "staging", live: false, domain: "staging.#{key}.test"}
    ]
  end

  defp site_attrs(key) do
    %{
      name: String.capitalize(key),
      key: key,
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end
