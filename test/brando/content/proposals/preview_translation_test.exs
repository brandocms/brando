defmodule Brando.Content.Proposals.PreviewTranslationTest do
  # `preview_proposal` of a synchronized translation's page. Not async:
  # pages are made synchronized through the application env
  # (`put_test_env(Page, …)`), which the async tests beside it would see.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Test.SiteRouter, as: Router
  alias Ecto.Adapters.SQL

  setup do
    Brando.ProposalFixtures.context()
  end

  defp mcp(c), do: %Context{actor: c.user, origin: :mcp, client: "Claude Code"}

  defp prepare!(context, operations, summary) do
    assert {:ok, %{proposal_id: id} = review} =
             Tools.call("prepare_proposal", %{"summary" => summary, "operations" => operations}, context)

    assert review.problems == [], inspect(review.problems)
    id
  end

  defp page(page), do: %{"content_type" => "Brando.Pages.Page", "id" => page.id}

  defp preview!(context, id, target) do
    assert {:ok, %{url: url}} =
             Tools.call(
               "preview_proposal",
               %{"proposal_id" => id, "target" => target, "preview_target" => "blocks"},
               context
             )

    url
  end

  # The link as a browser opens it: through a site's router, with no login
  defp open(url) do
    :get
    |> Plug.Test.conn("https://admin.test#{URI.parse(url).path}")
    |> Map.put(:host, "admin.test")
    |> Router.call(Router.init([]))
  end

  defp card_pages(c, opts \\ []) do
    Brando.Test.Support.put_test_env(Page, translatable: [mode: :synchronized])
    Brando.ProposalFixtures.card_pages(c.user, opts)
  end

  defp translate_kicker(units, scope, target, kicker),
    do: Brando.ProposalFixtures.translate_kicker(units, scope, target, kicker)

  describe "a synchronized translation the proposal translates" do
    setup c do
      pages = card_pages(c)
      {:ok, target} = Brando.Translations.create_target(Page, pages.source.id, :en, c.user)
      Map.put(pages, :target, target)
    end

    test "shows its new texts and the cards its links draw", c do
      {:ok, %{units: units}} = Brando.Translations.Work.translation_units(Page, c.target.id)
      scope = %{type: to_string(Page), id: c.target.id, language: "en"}
      op = translate_kicker(units, scope, page(c.target), c.kicker)

      id = prepare!(mcp(c), [op], "Translate the page")

      body = open(preview!(mcp(c), id, page(c.target))).resp_body
      assert body =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert body =~ ~s(<a class="card">Project</a>)
      refute body =~ "Våre prosjekter"
      refute body =~ "Prosjekt"
    end
  end

  describe "a translation the proposal creates" do
    setup c do
      card_pages(c)
    end

    defp create_op(source) do
      %{
        "op" => "create_translation",
        "source" => page(source),
        "language" => "en",
        "ref" => "english"
      }
    end

    defp translate_new(c) do
      {:ok, %{units: units}} = Brando.Translations.Work.new_translation_units(Page, c.source.id)
      scope = %{type: to_string(Page), id: {:new, c.source.id}, language: "en"}
      translate_kicker(units, scope, %{"new" => "english"}, c.kicker)
    end

    # The text the proposal translated is checked again as the copy is made,
    # as when the proposal is applied
    test "is refused once the source's text has changed", c do
      id = prepare!(mcp(c), [create_op(c.source), translate_new(c)], "Translate the page")
      {:ok, proposal} = Brando.Content.Proposals.get(id, c.user)

      Repo.update_all(from(v in Brando.Content.Var, where: v.key == "kicker"), set: [value: "Alle prosjekter"])

      assert {:error, message} =
               Brando.Content.Proposals.with_translation(proposal, {:new, "english"}, c.user, [], fn _ -> flunk() end)

      assert message =~ "changed"
    end

    # The copy's rows and the source's lock are held while the page renders,
    # for as long as the transaction may take. The connection is dropped
    # then, the test's sandbox with it, so nothing is read after.
    test "tells a render that outlasts its transaction", c do
      id = prepare!(mcp(c), [create_op(c.source)], "Add the English page")
      {:ok, proposal} = Brando.Content.Proposals.get(id, c.user)

      slow = fn _changeset ->
        Process.sleep(300)
        Repo.aggregate(Page, :count)
      end

      {result, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          Brando.Content.Proposals.with_translation(proposal, {:new, "english"}, c.user, [timeout: 100], slow)
        end)

      assert {:error, message} = result
      assert message =~ "took too long"
    end

    # A template reads the global locale (`Brando.HTML.I18n.translate/1`) or
    # the site's backend, as well as Brando's own
    test "renders in the caller's locales", c do
      id = prepare!(mcp(c), [create_op(c.source)], "Add the English page")
      {:ok, proposal} = Brando.Content.Proposals.get(id, c.user)
      backends = [Brando.Gettext, Brando.gettext()]
      Gettext.put_locale("no")
      for backend <- backends, do: Gettext.put_locale(backend, "no")

      locales = fn _changeset -> [Gettext.get_locale() | Enum.map(backends, &Gettext.get_locale/1)] end

      assert Brando.Content.Proposals.with_translation(proposal, {:new, "english"}, c.user, [], locales) ==
               ["no", "no", "no"]
    end

    test "is refused once the language is taken", c do
      id = prepare!(mcp(c), [create_op(c.source)], "Add the English page")
      {:ok, proposal} = Brando.Content.Proposals.get(id, c.user)
      {:ok, _} = Brando.Translations.create_target(Page, c.source.id, :en, c.user)

      # The page is not rendered for a proposal with problems; the copy is
      # checked again as it is made, as when the proposal is applied
      assert {:error, message} =
               Brando.Content.Proposals.with_translation(proposal, {:new, "english"}, c.user, [], fn _ -> flunk() end)

      assert message =~ "already has a version in this language"

      assert {:error, message} =
               Tools.call(
                 "preview_proposal",
                 %{"proposal_id" => id, "target" => %{"new" => "english"}, "preview_target" => "blocks"},
                 mcp(c)
               )

      assert message =~ "has problems"
    end
  end

  describe "a translation the proposal creates, in one environment of one of several sites" do
    alias Brando.Tenant

    # Both sites' schemas hold the same rows, so the same ids: each page's
    # text tells whose it is
    setup c do
      pages = card_pages(c)
      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      on_exit(fn -> Tenant.put_prefix(nil) end)

      alpha = site("Copy Alpha", "copy-alpha")
      beta = site("Copy Beta", "copy-beta")
      alpha_live = environment(alpha, "production")
      _beta_live = environment(beta, "production")
      beta_staging = environment(beta, "staging")

      for {environment, site, kicker} <- [
            {alpha_live, alpha, "Alfas prosjekter"},
            {beta_staging, beta, "Betas prosjekter"}
          ] do
        Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
          Repo.update_all(from(v in Brando.Content.Var, where: v.key == "kicker"), set: [value: kicker])
        end)
      end

      Map.merge(pages, %{prefix: Tenant.prefix(beta, beta_staging)})
    end

    defp site(name, key) do
      {:ok, site} =
        Tenant.Registry.create_site(%{
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
      {:ok, environment} = Tenant.Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
      prefix = Tenant.prefix(site, environment)
      SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))

      for [table] <-
            SQL.query!(Repo.repo(), "SELECT tablename FROM pg_tables WHERE schemaname = 'public'").rows,
          not Tenant.SharedTables.member?(table) do
        Ecto.Adapters.SQL.query!(
          Repo.repo(),
          ~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|
        )

        SQL.query!(Repo.repo(), ~s|INSERT INTO "#{prefix}"."#{table}" SELECT * FROM public."#{table}"|)
      end

      environment
    end

    # The page renders where the proposal was prepared, in a process of its own
    test "renders the copy made in that site's environment", c do
      Tenant.with_prefix(c.prefix, fn ->
        id = prepare!(mcp(c), [create_op(c.source)], "Add the English page")
        {:ok, proposal} = Brando.Content.Proposals.get(id, c.user)

        assert {:ok, %{html: html}} =
                 Brando.Content.Proposals.Preview.render(proposal, {:new, "english"}, c.user, preview_target: :blocks)

        assert html =~ ~s(<h2 class="kicker">Betas prosjekter</h2>)
        refute html =~ "Alfas prosjekter"
        refute html =~ "Våre prosjekter"
      end)
    end
  end

  describe "a translation the proposal creates, shared by one who may not export pages" do
    alias Brando.Authorization.Catalog, as: Grants
    alias Brando.Authorization.Groups
    alias Brando.Authorization.Scope

    setup c do
      pages = card_pages(c)
      Brando.Test.Support.put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      Repo.update_all(from(p in Page, where: p.id == ^pages.source.id), set: [status: :draft])

      editor = Factory.insert(:random_user, role: :user)

      grants =
        Enum.map([:read, :create, :update, :duplicate], &Grants.get(&1, Page).key) ++
          [Grants.get(:read, Brando.Content.Module).key, "brando.admin.access"]

      {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Page editors"}, grants)
      {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, editor.id)
      refute Brando.Authorization.Engine.can?(Scope.standalone(editor), :export, Page)

      Map.put(pages, :editor, editor)
    end

    # Refused before the site's assets are captured for the link
    test "is refused before anything is captured", c do
      context = %Context{actor: c.editor, origin: :mcp, client: "Claude Code"}
      id = prepare!(context, [create_op(c.source)], "Add the English page")
      {:ok, proposal} = Brando.Content.Proposals.get(id, c.editor)
      sets = Repo.aggregate(Brando.Assets.SiteAssetSet, :count)

      assert {:error, :forbidden} =
               Brando.Content.Proposals.Preview.share(proposal, {:new, "english"}, c.editor, preview_target: :blocks)

      assert Repo.aggregate(Brando.Assets.SiteAssetSet, :count) == sets
    end
  end

  describe "a synchronized translation whose source changed its meta image" do
    # A module that shows the entry's meta image. The source's image changes
    # after the translation was made: the pending version holds the new one.
    setup c do
      Brando.Test.Support.put_test_env(Page, translatable: [mode: :synchronized])

      banner =
        Brando.ProposalFixtures.module!(
          c.user,
          "Banner",
          ~s({% if entry.meta_image %}<img class="banner" src="{{ entry.meta_image.path }}">{% endif %}),
          []
        )

      first = Factory.insert(:image, path: "images/first.jpg", creator_id: c.user.id)
      second = Factory.insert(:image, path: "images/second.jpg", creator_id: c.user.id)

      source =
        Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: c.user, meta_image_id: first.id)

      block =
        %Brando.Content.Block{}
        |> Brando.Content.Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => banner.id,
            "creator_id" => c.user.id,
            "source" => to_string(Page.Blocks)
          },
          c.user
        )
        |> Repo.insert!()

      struct(Page.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()

      {:ok, target} = Brando.Translations.create_target(Page, source.id, :en, c.user)
      assert Repo.get!(Page, target.id).meta_image_id == first.id

      source |> Ecto.Changeset.change(meta_image_id: second.id) |> Repo.update!()
      {:ok, source} = Brando.Translations.load_entry(Page, source.id)
      Brando.Translations.source_saved(source)

      %{target: target}
    end

    test "is saved with the source's image now", c do
      {:ok, proposal} = Brando.Content.Proposals.propose([translate(c.target)], c.user)
      assert proposal.problems == []
      {:ok, _} = Brando.Content.Proposals.approve(proposal.id, proposal.version, c.user)
      {:ok, _} = Brando.Content.Proposals.apply(proposal.id, proposal.version, c.user)

      rendered = Repo.get!(Page, c.target.id).rendered_blocks
      assert rendered =~ "images/second.jpg"
      refute rendered =~ "images/first.jpg"
    end

    test "is previewed with the source's image now", c do
      op = c.target |> translate() |> Brando.Content.Proposals.Codec.encode()
      id = prepare!(mcp(c), [op], "Translate the page")

      body = open(preview!(mcp(c), id, page(c.target))).resp_body
      assert body =~ "images/second.jpg"
      refute body =~ "images/first.jpg"
    end
  end

  # The page's title, translated
  defp translate(target) do
    {:ok, %{units: units}} = Brando.Translations.Work.translation_units(Page, target.id)
    units = Enum.filter(units, &(&1.answerable and &1.key == "title"))
    digest = Brando.Translations.Work.token(%{type: to_string(Page), id: target.id, language: "en"}, units)

    %Brando.Content.Proposals.Translate{target: {Page, target.id}, source_digest: digest, texts: %{"title" => "About us"}}
  end
end
