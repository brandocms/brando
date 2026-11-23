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

  # A source page with a card drawn only when its link var's identifier is
  # there, linked to a page that has an English version, and a kicker to
  # translate: the pending version points the card at the English page.
  defp card_pages(c, opts \\ []) do
    Brando.Test.Support.put_test_env(Page, translatable: [mode: :synchronized])

    card =
      Brando.ProposalFixtures.module!(
        c.user,
        "Card",
        ~s(<h2 class="kicker">{{ kicker }}</h2>) <>
          ~s({% if project and project.identifier %}<a class="card">{{ project.identifier.title }}</a>{% endif %}),
        vars: [
          %{key: "kicker", type: "string", label: "Kicker"},
          %{key: "project", type: "link", label: "Project", link_type: "identifier"}
        ]
      )

    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: c.user)
    other = Factory.insert(:page, title: "Prosjekt", uri: "prosjekt", language: :no, creator: c.user)
    {:ok, identifier} = Brando.Content.create_identifier(Page, other)

    block =
      %Brando.Content.Block{}
      |> Brando.Content.Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => card.id,
          "creator_id" => c.user.id,
          "source" => to_string(Page.Blocks)
        },
        c.user
      )
      |> Repo.insert!()

    Repo.insert!(%Brando.Content.Var{
      key: "kicker",
      type: :string,
      label: %{"en" => "Kicker"},
      value: "Våre prosjekter",
      block_id: block.id,
      sequence: 0
    })

    Repo.insert!(%Brando.Content.Var{
      key: "project",
      type: :link,
      link_type: :identifier,
      label: %{"en" => "Project"},
      identifier_id: identifier.id,
      block_id: block.id,
      sequence: 1
    })

    struct(Page.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()

    if Keyword.get(opts, :other_en, true) do
      {:ok, other_en} = Brando.Translations.create_target(Page, other.id, :en, c.user)
      {:ok, _} = Brando.Pages.update_page(other_en.id, %{title: "Project"}, c.user)
    end

    %{source: source, other: other, kicker: "entry_blocks/#{block.uid}/vars/kicker/value"}
  end

  # The batch translating the kicker, as translation_work gives its token
  defp translate_kicker(units, scope, target, kicker) do
    units = Enum.filter(units, &(&1.answerable and &1.key == kicker))
    assert [_] = units

    %{
      "op" => "translate",
      "target" => target,
      "source_digest" => Brando.Translations.Work.token(scope, units),
      "texts" => %{kicker => "Our projects"}
    }
  end

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

    # Every row a preview could leave behind, but the snapshot and its purger
    defp kept do
      schemas = [
        Page,
        Brando.Content.Block,
        Brando.Content.Var,
        Brando.Content.Identifier,
        Brando.Translations.Group,
        Brando.Translations.Member,
        Brando.Translations.PendingVersion,
        Brando.Translations.WorkItem,
        Brando.Activity.Event
      ]

      counts = Map.new(schemas, &{&1, Repo.aggregate(&1, :count)})

      jobs =
        Repo.aggregate(
          from(j in Oban.Job, where: j.worker != "Brando.Worker.PreviewPurger"),
          :count
        )

      Map.put(counts, Oban.Job, jobs)
    end

    test "shows the copy with the proposal's texts and its links, keeping nothing", c do
      id = prepare!(mcp(c), [create_op(c.source), translate_new(c)], "Translate the page")

      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(Page)}"))
      before = kept()
      # The render reads the card's module through the query cache, which
      # would keep it
      Cachex.clear(:query)

      body = open(preview!(mcp(c), id, %{"new" => "english"})).resp_body
      assert body =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert body =~ ~s(<a class="card">Project</a>)
      refute body =~ "Våre prosjekter"
      refute body =~ "Prosjekt"

      assert kept() == before
      assert Cachex.size!(:query) == 0
      # Broadcasts are held for a commit, which the rollback never makes
      refute_received {:mutation, _, _, _}
      assert Brando.Translations.get_member(Page, c.source.id) == nil
    end

    # The listing's assigns hold the copy's id and title, gone once rolled back
    test "keeps none of the view's assigns", c do
      id = prepare!(mcp(c), [create_op(c.source), translate_new(c)], "Translate the page")

      assert {:ok, %{url: url}} =
               Tools.call(
                 "preview_proposal",
                 %{"proposal_id" => id, "target" => %{"new" => "english"}, "preview_target" => "listing"},
                 mcp(c)
               )

      assert open(url).resp_body =~ "Om oss"

      # Async tests beside it keep their own
      {:ok, keys} = Cachex.keys(:cache)

      assert for(
               key <- keys,
               is_binary(key) and key =~ "__VAR__employees",
               {:ok, [%{name: "Om oss"}]} = Cachex.get(:cache, key),
               do: key
             ) == []
    end

    test "shows the untranslated copy without a translate", c do
      id = prepare!(mcp(c), [create_op(c.source)], "Add the English page")
      before = kept()

      body = open(preview!(mcp(c), id, %{"new" => "english"})).resp_body
      assert body =~ ~s(<h2 class="kicker">Våre prosjekter</h2>)
      assert body =~ ~s(<a class="card">Project</a>)

      assert kept() == before
    end

    # The admin's review renders the same page into its frame, and shares it
    test "shows the review's page preview and shareable link, keeping nothing", c do
      id = prepare!(mcp(c), [create_op(c.source), translate_new(c)], "Translate the page")
      {:ok, proposal} = Brando.Content.Proposals.get(id, c.user)
      assert Brando.Content.Proposals.Review.preview_key(proposal) == "new:english"
      before = kept()

      assert {:ok, %{key: key, html: html}} =
               Brando.Content.Proposals.Preview.render(proposal, {:new, "english"}, c.user, preview_target: :blocks)

      assert html =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert html =~ ~s(<a class="card">Project</a>)
      # The frame opens for its editor, though the copy is gone
      assert Brando.Authorization.Preview.authorize(key, c.user.id) == :ok
      Brando.Content.Proposals.Preview.discard([key])

      assert {:ok, url, _days} =
               Brando.Content.Proposals.Preview.share(proposal, {:new, "english"}, c.user, preview_target: :blocks)

      assert open(url).resp_body =~ ~s(<h2 class="kicker">Our projects</h2>)
      assert kept() == before
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

  describe "a translation the proposal creates beside the one its link points at" do
    setup c do
      card_pages(c, other_en: false)
    end

    # The page's card links the project, which the same proposal translates
    # too: the preview has the project's English version, as applying makes it
    test "links the proposal's other translation", c do
      {:ok, %{units: units}} = Brando.Translations.Work.new_translation_units(Page, c.other.id)
      units = Enum.filter(units, &(&1.answerable and &1.key == "title"))
      scope = %{type: to_string(Page), id: {:new, c.other.id}, language: "en"}

      title = %{
        "op" => "translate",
        "target" => %{"new" => "project"},
        "source_digest" => Brando.Translations.Work.token(scope, units),
        "texts" => %{"title" => "Project"}
      }

      operations = [
        %{"op" => "create_translation", "source" => page(c.other), "language" => "en", "ref" => "project"},
        title,
        create_op(c.source)
      ]

      id = prepare!(mcp(c), operations, "Translate the pages")
      before = kept()

      body = open(preview!(mcp(c), id, %{"new" => "english"})).resp_body
      assert body =~ ~s(<a class="card">Project</a>)
      refute body =~ "Prosjekt"
      assert kept() == before
      assert Brando.Translations.get_member(Page, c.other.id) == nil
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
