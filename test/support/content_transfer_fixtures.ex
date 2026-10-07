defmodule Brando.ContentTransferFixtures do
  @moduledoc false
  # The pages, module and media the content transfer screen is tested with.
  # The same content as the E2E fixtures in
  # e2e/test/support/e2e_fixture_controller.ex (`create_content_transfer/0`
  # and `create_content_transfer_media/0`), built for a given user.

  alias Brando.Content
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock

  @module_name %{"en" => "Campaign introduction"}

  @doc """
  "Campaign launch" (published, with an introduction block), "Destination
  page" (published, with an older introduction) and a draft.
  """
  def content_transfer(user) do
    module =
      Repo.insert!(%Content.Module{
        uid: Ecto.UUID.generate(),
        type: :liquid,
        name: @module_name,
        class: "campaign-introduction",
        namespace: %{"en" => "Content"},
        help_text: %{},
        code: "{% ref refs.body %}",
        refs: [
          %Content.Ref{
            name: "body",
            uid: Brando.Utils.generate_uid(),
            data: %TextBlock{type: "text", data: %TextBlock.Data{text: ""}}
          }
        ],
        vars: []
      })

    [source, destination, _draft] =
      Enum.map(
        [
          {"Campaign launch", "campaign-launch", :published},
          {"Destination page", "destination-page", :published},
          {"Autumn collection: the people, places and stories behind it", "autumn-collection", :draft}
        ],
        fn {title, uri, status} ->
          page =
            Repo.insert!(%Page{
              title: title,
              meta_title: if(uri == "campaign-launch", do: "A new collection, made with care"),
              meta_description:
                if(uri == "campaign-launch", do: "Discover the people and ideas behind our next collection."),
              uri: uri,
              language: :en,
              status: status,
              template: "default.html",
              creator_id: user.id
            })

          Content.create_identifier(Page, page)
          page
        end
      )

    params = %{
      "uid" => Brando.Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Page.Blocks),
      "description" => "Introduction",
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "body",
          "data" => %{"type" => "text", "data" => %{"text" => "<p>A considered introduction to our next collection.</p>"}}
        }
      ]
    }

    block = %Content.Block{} |> Content.Block.recursive_block_changeset(params, user) |> Repo.insert!()
    Repo.insert!(struct(Page.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}))

    previous =
      params
      |> Map.put("uid", Brando.Utils.generate_uid())
      |> put_in(["refs", Access.at(0), "uid"], Brando.Utils.generate_uid())
      |> put_in(
        ["refs", Access.at(0), "data", "data", "text"],
        "<p>Discover the stories behind our previous collection.</p>"
      )

    previous = %Content.Block{} |> Content.Block.recursive_block_changeset(previous, user) |> Repo.insert!()
    Repo.insert!(struct(Page.Blocks, %{entry_id: destination.id, block_id: previous.id, sequence: 0}))

    %{source: source, destination: destination, module: module}
  end

  @doc "As `content_transfer/1`, with Campaign launch a child of Destination page."
  def content_transfer_related(user) do
    fixture = content_transfer(user)
    source = fixture.source |> Ecto.Changeset.change(parent_id: fixture.destination.id) |> Repo.update!()
    %{fixture | source: source}
  end

  @doc """
  As `content_transfer/1`, with picture refs on both pages: the source's hero
  is replaced (and gets alt text) and its detail image moves to a later block.
  """
  def content_transfer_media(user) do
    fixture = content_transfer(user)

    [old, replacement, moved] =
      Enum.map(~w(coastal-house.jpg courtyard.jpg collection-detail.jpg), fn name ->
        Repo.insert!(%Brando.Images.Image{
          path: "images/" <> name,
          width: 1200,
          height: 800,
          sizes: %{},
          formats: [:jpg],
          status: :processed,
          config_target: "default",
          creator_id: user.id
        })
      end)

    picture = fn name, label, image, sequence ->
      %Content.Ref{
        name: name,
        description: label,
        image_id: image && image.id,
        sequence: sequence,
        uid: Brando.Utils.generate_uid(),
        data: %PictureBlock{type: "picture", data: %PictureBlock.Data{}}
      }
    end

    for {name, label, sequence} <- [{"cover", "Hero", 1}, {"detail", "Detail", 2}] do
      name |> picture.(label, nil, sequence) |> Map.put(:module_id, fixture.module.id) |> Repo.insert!()
    end

    for {page, cover, detail_here, detail_below} <- [
          {fixture.source, replacement, nil, moved},
          {fixture.destination, old, moved, nil}
        ] do
      join = Repo.get_by!(Page.Blocks, entry_id: page.id)

      for ref <- [picture.("cover", "Hero", cover, 1), picture.("detail", "Detail", detail_here, 2)] do
        ref |> Map.put(:block_id, join.block_id) |> Repo.insert!()
      end

      story =
        Repo.insert!(%Content.Block{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          module_id: fixture.module.id,
          creator_id: user.id,
          source: to_string(Page.Blocks),
          description: "The details",
          refs: [picture.("detail", "Detail", detail_below, 0)]
        })

      Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: story.id, sequence: 1}))
    end

    # A placement-only alt text change should appear next to its image.
    join = Repo.get_by!(Page.Blocks, entry_id: fixture.source.id, sequence: 0)
    ref = Repo.get_by!(Content.Ref, block_id: join.block_id, name: "cover")
    data = %{ref.data | data: %{ref.data.data | alt: "The courtyard in morning light"}}
    ref |> Ecto.Changeset.change(data: data) |> Repo.update!()

    fixture
  end

  @doc """
  A bundle of the source's blocks as another installation would send it: the
  module it uses has a different uid here, so its definition is missing.
  """
  def unmatched_bundle(fixture, user) do
    {:ok, exported} =
      Content.Transfer.export([%{schema: Page, id: fixture.source.id, fields: ["blocks"]}], user)

    module = Repo.preload(fixture.module, :refs)
    module |> Ecto.Changeset.change(uid: Ecto.UUID.generate()) |> Repo.update!()

    Enum.each(module.refs, fn ref ->
      ref |> Ecto.Changeset.change(uid: Brando.Utils.generate_uid()) |> Repo.update!()
    end)

    bundle =
      exported.bundle
      |> put_in(["source", "scope"], "external-test-installation")
      |> put_in(["definitions", "source"], "external-test-installation")

    {:ok, binary} = Content.Transfer.Archive.export(bundle, exported.files)
    binary
  end
end
