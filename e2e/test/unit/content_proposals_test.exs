defmodule E2eProject.ContentProposalsTest do
  use E2eProject.DataCase, async: false
  alias Brando.{Content, Repo}
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{CreateEntry, InsertBlock, Preview}
  alias Brando.Pages.Page
  alias E2eProject.Projects.{Client, Project}

  test "a new case and a category page preview unsaved in the site's own templates, then apply" do
    suffix = String.slice(Ecto.UUID.generate(), 0, 8)

    actor =
      Repo.insert!(%Brando.Users.User{
        name: "Proposal test",
        email: "proposal-#{suffix}@brandocms.com",
        role: :superuser,
        password: "brandocms",
        language: :en
      })

    image =
      Repo.insert!(%Brando.Images.Image{
        path: "images/proposals/sommerro.jpg",
        width: 1200,
        height: 800,
        formats: [:jpg],
        sizes:
          Map.new(
            ~w(micro thumb small medium large xlarge xlarge_crop),
            &{&1, "images/proposals/#{&1}/sommerro.jpg"}
          ),
        config_target: "default",
        creator_id: actor.id
      })

    video =
      Repo.insert!(%Brando.Videos.Video{
        type: :youtube,
        source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        remote_id: "dQw4w9WgXcQ",
        width: 1920,
        height: 1080
      })

    {:ok, module} =
      Content.create_module(
        %{
          uid: "proposal" <> suffix,
          name: %{"en" => "Case"},
          namespace: %{"en" => "Cases"},
          help_text: %{"en" => "A case with media"},
          class: "case",
          code:
            ~s(<section class="case">{{ heading }}{% ref refs.cover %}{% ref refs.slot %}</section>),
          refs: [
            %{
              name: "cover",
              uid: Brando.Utils.generate_uid(),
              data: %{type: "picture", data: %{}}
            },
            %{
              name: "slot",
              uid: Brando.Utils.generate_uid(),
              data: %{
                type: "media",
                data: %{available_blocks: ["picture", "video"], template_video: %{}}
              }
            }
          ],
          vars: [%{type: "string", key: "heading", label: "Heading", value: "Heading"}]
        },
        actor
      )

    client =
      %Client{}
      |> Client.changeset(
        %{name: "Sommerro AS", slug: "client-" <> suffix, language: "en", status: "draft"},
        actor
      )
      |> Repo.insert!()

    # Projects.Category has no block field; a page stands in for the category.
    page =
      Repo.insert!(%Page{
        title: "Identity",
        uri: "identity-" <> suffix,
        language: :en,
        status: :published,
        template: "default.html",
        creator_id: actor.id
      })

    ops = [
      %CreateEntry{
        schema: Project,
        ref: "sommerro",
        fields: %{
          title: "Sommerro",
          slug: "sommerro-" <> suffix,
          introduction: "<p>A hotel in Oslo</p>",
          language: "en",
          client_id: client.id,
          listing_image_id: image.id
        }
      },
      %InsertBlock{
        target: {:new, "sommerro"},
        module: module.id,
        values: %{heading: "Sommerro story"},
        media: %{cover: {:image, image.id}}
      },
      %InsertBlock{
        target: {Page, page.id},
        module: module.id,
        values: %{heading: "Identity case"},
        media: %{slot: {:video, video.id}}
      }
    ]

    {:ok, proposal} = Proposals.prepare(ops, actor)
    assert proposal.problems == []
    assert proposal.effects.live == [{Page, page.id}]
    projects = Repo.aggregate(Project, :count)

    # The case has no id yet. Its page renders from the in-memory entry: the
    # listing image preloads through its foreign key, blocks from the proposal.
    assert {:ok, %{key: case_key, html: case_html}} =
             Preview.render(proposal, {:new, "sommerro"}, actor)

    assert case_html =~ "<h2>Sommerro</h2>"
    assert case_html =~ "Sommerro story"
    assert case_html =~ image.sizes["xlarge"]

    assert {:error, :not_created} =
             Preview.render(proposal, {:new, "sommerro"}, actor, version: :before)

    assert {:ok, %{key: page_key, html: page_html}} =
             Preview.render(proposal, {Page, page.id}, actor)

    assert page_html =~ "Identity case"
    assert page_html =~ "dQw4w9WgXcQ"

    assert {:ok, %{html: before_html}} =
             Preview.render(proposal, {Page, page.id}, actor, version: :before)

    refute before_html =~ "Identity case"

    Preview.discard([case_key, page_key])
    assert Repo.aggregate(Project, :count) == projects

    {:ok, receipt} = Proposals.apply(proposal, actor)
    project = Repo.get!(Project, receipt.mappings["created"]["sommerro"])
    assert project.status == :draft
    assert project.listing_image_id == image.id
    assert project.rendered_blocks =~ "Sommerro story"
    assert Repo.get!(Page, page.id).rendered_blocks =~ "Identity case"
  end
end
