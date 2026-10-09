defmodule Brando.Content.UsageTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Content.TableRow
  alias Brando.Content.Usage
  alias Brando.Content.Var
  alias Brando.Drafts.EntryDraft
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Videos

  test "a video is used by the page owning the block it sits in, and by galleries holding it" do
    page = Factory.insert(:page, title: "Om oss")
    Brando.Content.create_identifier(Page, page)

    in_block = Factory.insert(:video)
    in_gallery = Factory.insert(:video)
    unused = Factory.insert(:video)

    source = "Elixir.Brando.Pages.Page.Blocks"
    root = Brando.Repo.insert!(%Block{type: :container, source: source, uid: "rootblock00000000000001"})
    child = Brando.Repo.insert!(%Block{type: :module, source: source, parent_id: root.id, uid: "childblock0000000000001"})
    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: root.id, sequence: 0})
    Factory.insert(:ref, block_id: child.id, video_id: in_block.id)

    gallery = Factory.insert(:gallery)
    Factory.insert(:gallery_object, gallery_id: gallery.id, video_id: in_gallery.id)

    usage = Usage.list(:video, [in_block.id, in_gallery.id, unused.id])

    assert [%{label: "Om oss"}] = usage[in_block.id]
    assert [%{label: label}] = usage[in_gallery.id]
    assert label =~ "#{gallery.id}"
    refute Map.has_key?(usage, unused.id)

    {:ok, videos} = Videos.list_videos(%{filter: %{unused: "true"}})
    ids = Enum.map(videos, & &1.id)
    assert unused.id in ids
    refute in_block.id in ids
    refute in_gallery.id in ids
  end

  test "an image is used by a video it is the thumbnail of, named by the video's title" do
    image = Factory.insert(:image)
    unused = Factory.insert(:image)
    video = Factory.insert(:video, title: "Sommerro", thumbnail_id: image.id)

    assert [%{label: "Sommerro", url: url}] = Usage.list(:image, [image.id, unused.id])[image.id]
    assert url =~ "#{video.id}"
    assert image.id in Usage.used_ids(:image)
    refute unused.id in Usage.used_ids(:image)

    {:ok, images} = Brando.Images.list_images(%{filter: %{unused: "true"}})
    assert unused.id in Enum.map(images, & &1.id)
    refute image.id in Enum.map(images, & &1.id)
  end

  test "put/2 fills in each entry's usage, empty where it is used nowhere" do
    image = Factory.insert(:image)
    assert [%{usage: []}] = Usage.put([image], :image)
  end

  # A page showing one block, its root; returns the block.
  defp page_block(title) do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title))
    Brando.Content.create_identifier(Page, page)
    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Brando.Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    {page, block}
  end

  defp media_file,
    do: Brando.Repo.insert!(%Brando.Files.File{filename: "prices.pdf", filesize: 1, config_target: "default"})

  test "an image, a video and a file in a table block's row are used by the page owning the block" do
    {_page, block} = page_block("Downloads")
    row = Brando.Repo.insert!(%TableRow{block_id: block.id, sequence: 0})
    assets = [image: Factory.insert(:image), video: Factory.insert(:video), file: media_file()]

    for {kind, asset} <- assets do
      Brando.Repo.insert!(
        struct(Var, [
          {:"#{kind}_id", asset.id},
          type: kind,
          key: "#{kind}",
          label: %{"en" => "Download"},
          table_row_id: row.id
        ])
      )

      assert [%{label: "Downloads"}] = Usage.list(kind, [asset.id])[asset.id]
      assert asset.id in Usage.used_ids(kind)
    end

    {:ok, files} = Brando.Files.list_files(%{filter: %{unused: "true"}})
    refute assets[:file].id in Enum.map(files, & &1.id)
  end

  test "an entry in the trash still uses its assets, though Used in leaves it out" do
    {page, block} = page_block("Old campaign")
    in_block = Factory.insert(:video)
    Factory.insert(:ref, block_id: block.id, video_id: in_block.id)
    thumbnail = Factory.insert(:image)
    Factory.insert(:video, thumbnail_id: thumbnail.id, deleted_at: DateTime.utc_now())

    Brando.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [deleted_at: DateTime.utc_now()])

    assert Usage.list(:video, [in_block.id]) == %{}
    assert Usage.list(:image, [thumbnail.id]) == %{}
    assert in_block.id in Usage.used_ids(:video)
    assert thumbnail.id in Usage.used_ids(:image)
  end

  test "an asset an open recovery draft holds is used; a discarded draft's is not" do
    user = Factory.insert(:random_user)
    [in_ref, in_field, discarded] = for _ <- 1..3, do: Factory.insert(:image)

    draft = fn payload, extra ->
      Brando.Repo.insert!(
        struct(
          %EntryDraft{
            id: Ecto.UUID.generate(),
            scope: Brando.Drafts.scope(),
            owner_id: user.id,
            entry_type: "Elixir.Brando.Pages.Page",
            form_name: "page_form",
            generation: 1,
            base_fingerprint: "x",
            payload: payload,
            checksum: "x",
            expires_at: DateTime.add(DateTime.utc_now(), 3600)
          },
          extra
        )
      )
    end

    draft.(%{"blocks" => [%{"block" => %{"refs" => [%{"image_id" => in_ref.id}]}}], "meta_image_id" => in_field.id}, [])
    draft.(%{"meta_image_id" => discarded.id}, discarded_at: DateTime.utc_now())

    used = Usage.used_ids(:image)
    assert in_ref.id in used
    assert in_field.id in used
    refute discarded.id in used
  end

  describe "tenancy" do
    @prefix "tenant_usage_production"
    @cache {Usage, :asset_fields, @prefix}

    setup do
      put_test_env(:tenancy_mode, :multi)
      :persistent_term.erase(@cache)
      on_exit(fn -> :persistent_term.erase(@cache) end)
      BrandoIntegration.Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

      # Not every table: projects, say, has not been migrated in this site.
      for table <- ~w(files videos content_blocks content_refs content_vars content_table_rows content_identifiers) do
        BrandoIntegration.Repo.query!(~s|CREATE TABLE "#{@prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      :ok
    end

    test "Blueprint asset fields are looked up in the site's own schema" do
      Brando.Tenant.with_prefix(@prefix, fn ->
        file = media_file()
        unused = media_file()
        video = Brando.Repo.insert!(%Brando.Videos.Video{type: :upload, file_id: file.id})

        assert [%{url: url}] = Usage.list(:file, [file.id, unused.id])[file.id]
        assert url =~ "#{video.id}"
        assert file.id in Usage.used_ids(:file)
        refute unused.id in Usage.used_ids(:file)
      end)
    end
  end

  describe "assets in blocks under tenancy" do
    @block_prefix "tenant_usage_blocks"

    setup do
      put_test_env(:tenancy_mode, :multi)
      on_exit(fn -> :persistent_term.erase({Usage, :asset_fields, @block_prefix}) end)
      BrandoIntegration.Repo.query!(~s(CREATE SCHEMA "#{@block_prefix}"))

      for table <-
            ~w(images videos files pages pages_blocks pages_alternates content_blocks content_refs content_vars content_table_rows content_identifiers galleries_gallery_objects) do
        BrandoIntegration.Repo.query!(~s|CREATE TABLE "#{@block_prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      %{user: Factory.insert(:random_user)}
    end

    test "a block's variables and refs use their images, videos and files in the site's own schema", c do
      Brando.Tenant.with_prefix(@block_prefix, fn ->
        page =
          Brando.Repo.insert!(%Page{
            title: "Om oss",
            uri: "om-oss",
            language: :en,
            template: "default.html",
            creator_id: c.user.id
          })

        Brando.Repo.insert!(%Brando.Content.Identifier{
          schema: Page,
          entry_id: page.id,
          title: "Om oss",
          status: :published,
          language: :en,
          updated_at: DateTime.utc_now(:second)
        })

        source = "Elixir.Brando.Pages.Page.Blocks"
        block = Brando.Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
        Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})

        assets = [
          image: fn -> Brando.Repo.insert!(Factory.build(:image)) end,
          video: fn -> Brando.Repo.insert!(Factory.build(:video)) end,
          file: &media_file/0
        ]

        for {kind, new} <- assets do
          [in_var, in_ref, unused] = [new.(), new.(), new.()]

          Brando.Repo.insert!(
            struct(Var, [
              {:"#{kind}_id", in_var.id},
              type: kind,
              key: "#{kind}",
              label: %{"en" => "A"},
              block_id: block.id
            ])
          )

          Brando.Repo.insert!(Map.put(Factory.build(:ref, block_id: block.id), :"#{kind}_id", in_ref.id))

          used = Usage.used_ids(kind)
          assert in_var.id in used
          assert in_ref.id in used
          refute unused.id in used
          assert [%{label: "Om oss"}] = Usage.list(kind, [in_ref.id])[in_ref.id]

          # What the library's Not in use filter, and so Delete unused, lists
          list = %{
            image: &Brando.Images.list_images/1,
            video: &Brando.Videos.list_videos/1,
            file: &Brando.Files.list_files/1
          }

          {:ok, listed} = list[kind].(%{filter: %{unused: "true"}, select: [:id]})
          assert Enum.map(listed, & &1.id) == [unused.id]
        end
      end)
    end
  end
end
