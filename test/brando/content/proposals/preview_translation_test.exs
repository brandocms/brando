defmodule Brando.Content.Proposals.PreviewTranslationTest do
  # `preview_proposal` of a synchronized translation's page. Not async:
  # pages are made synchronized through the application env
  # (`put_test_env(Page, …)`), which the async tests beside it would see.
  use Brando.ConnCase, async: false

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

  describe "a synchronized translation the proposal translates" do
    # A card drawn only when its link var's identifier is there, linked to a
    # page translated after the translation was made: the pending version
    # points the card at the English page.
    setup c do
      Brando.Test.Support.put_test_env(Page, translatable: [mode: :synchronized])

      card =
        Brando.ProposalFixtures.module!(
          c.user,
          "Card",
          ~s({% if project and project.identifier %}<a class="card">{{ project.identifier.title }}</a>{% endif %}),
          vars: [%{key: "project", type: "link", label: "Project", link_type: "identifier"}]
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
        key: "project",
        type: :link,
        link_type: :identifier,
        label: %{"en" => "Project"},
        identifier_id: identifier.id,
        block_id: block.id,
        sequence: 0
      })

      struct(Page.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()

      {:ok, target} = Brando.Translations.create_target(Page, source.id, :en, c.user)
      {:ok, other_en} = Brando.Translations.create_target(Page, other.id, :en, c.user)
      {:ok, _} = Brando.Pages.update_page(other_en.id, %{title: "Project"}, c.user)

      %{target: target}
    end

    test "shows the cards its links draw", c do
      {:ok, %{units: units}} = Brando.Translations.Work.translation_units(Page, c.target.id)
      units = Enum.filter(units, &(&1.answerable and &1.key == "title"))
      digest = Brando.Translations.Work.token(%{type: to_string(Page), id: c.target.id, language: "en"}, units)

      op = %{
        "op" => "translate",
        "target" => page(c.target),
        "source_digest" => digest,
        "texts" => %{"title" => "About us"}
      }

      id = prepare!(mcp(c), [op], "Translate the page")

      body = open(preview!(mcp(c), id, page(c.target))).resp_body
      assert body =~ ~s(<a class="card">Project</a>)
      refute body =~ "Prosjekt"
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
