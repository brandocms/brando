defmodule Brando.Drafts.MediaTest do
  use Brando.ConnCase, async: false

  alias Brando.Drafts
  alias Brando.Drafts.Modules
  alias Brando.Drafts.Params
  alias Brando.Drafts.Restore
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, page} = Brando.Blueprint.EntryQuery.get(Page, page.id)
    images = [Factory.insert(:image), Factory.insert(:image)]
    video = Factory.insert(:video)

    file =
      Repo.insert!(%Brando.Files.File{
        filename: "draft.pdf",
        mime_type: "application/pdf",
        filesize: 42,
        config_target: "default",
        creator_id: user.id
      })

    refs =
      Enum.map([{"photo", "picture"}, {"clip", "video"}, {"collection", "gallery"}], fn {name, type} ->
        %{name: name, uid: Brando.Utils.generate_uid(), data: %{type: type, data: %{}}}
      end)

    vars =
      Enum.map([{"photo_var", :image}, {"clip_var", :video}, {"download", :file}], fn {key, type} ->
        %{key: key, label: key, type: type}
      end)

    {:ok, module} = Brando.Content.create_module(Factory.params_for(:module, refs: refs, vars: vars), user)

    block =
      BrandoAdmin.Components.Form.BlockField.build_block(
        module.id,
        user.id,
        nil,
        Page.__schema__(:association, :entry_blocks).queryable,
        :module
      )
      |> Params.snapshot()

    block =
      block
      |> Map.update!("refs", fn refs ->
        Enum.map(refs, fn
          %{"name" => "photo"} = ref ->
            ref |> Map.put("image_id", hd(images).id) |> put_in(["data", "data", "title"], "Usage caption")

          %{"name" => "clip"} = ref ->
            ref |> Map.put("video_id", video.id) |> put_in(["data", "data", "autoplay"], true)

          %{"name" => "collection"} = ref ->
            Map.put(ref, "gallery", %{
              "config_target" => "default",
              "gallery_objects" => [
                %{
                  "image_id" => hd(images).id,
                  "sequence" => 0,
                  "config" => %{"caption" => "Gallery caption", "focal" => %{"x" => 25, "y" => 70}}
                },
                %{"video_id" => video.id, "sequence" => 1, "config" => %{"autoplay" => true}},
                %{"image_id" => List.last(images).id, "sequence" => 2, "config" => %{}}
              ]
            })
        end)
      end)
      |> Map.update!("vars", fn vars ->
        Enum.map(vars, fn
          %{"key" => "photo_var"} = var -> Map.put(var, "image_id", hd(images).id)
          %{"key" => "clip_var"} = var -> Map.put(var, "video_id", video.id)
          %{"key" => "download"} = var -> Map.put(var, "file_id", file.id)
        end)
      end)

    {:ok, user: user, page: page, images: images, video: video, asset_file: file, block: block}
  end

  defp recover(ctx, page, row) do
    fields = %{"blocks" => [row]}
    payload = %{"main" => %{}, "blocks" => fields, "modules" => Modules.manifest(fields)}
    identity = Drafts.identity(Page, page.id, ctx.user.id)
    id = Ecto.UUID.generate()

    assert {:ok, _} =
             Drafts.write(
               identity,
               id,
               1,
               payload,
               Drafts.fingerprint(page),
               Brando.Blueprint.Snapshot.get_current_version(Page)
             )

    assert {:ok, cs, []} = Restore.prepare(Drafts.get(identity, id), page, Page, ctx.user)
    assert cs.valid?, inspect(Changeset.traverse_errors(cs, &inspect/1))
    cs
  end

  defp asset_counts,
    do: Enum.map([Brando.Images.Image, Brando.Videos.Video, Brando.Files.File], &Repo.aggregate(&1, :count))

  defp block(page), do: hd(page.entry_blocks).block
  defp ref(page, name), do: Enum.find(block(page).refs, &(&1.name == name))

  test "JSON recovery preserves media refs, vars, usage overrides and a new mixed gallery", ctx do
    counts = asset_counts()
    join = Page.__schema__(:association, :entry_blocks).queryable
    row = join.changeset(struct(join), %{"block" => ctx.block}, ctx.user.id, true) |> Params.snapshot()
    restored = recover(ctx, ctx.page, row)
    Repo.update!(restored)
    {:ok, page} = Brando.Blueprint.EntryQuery.get(Page, ctx.page.id)
    assert ref(page, "photo").image_id == hd(ctx.images).id
    assert ref(page, "photo").data.data.title == "Usage caption"
    assert ref(page, "clip").video_id == ctx.video.id
    assert ref(page, "clip").data.data.autoplay
    vars = Map.new(block(page).vars, &{&1.key, &1})
    assert vars["photo_var"].image_id == hd(ctx.images).id
    assert vars["clip_var"].video_id == ctx.video.id
    assert vars["download"].file_id == ctx.asset_file.id
    objects = ref(page, "collection").gallery.gallery_objects

    assert Enum.map(objects, &{&1.image_id, &1.video_id, &1.sequence}) == [
             {hd(ctx.images).id, nil, 0},
             {nil, ctx.video.id, 1},
             {List.last(ctx.images).id, nil, 2}
           ]

    assert hd(objects).config["caption"] == "Gallery caption"
    assert hd(objects).config["focal"] == %{"x" => 25, "y" => 70}
    assert asset_counts() == counts
    assert Repo.get!(Brando.Images.Image, hd(ctx.images).id).title == hd(ctx.images).title
  end

  test "persisted gallery recovery keeps owned IDs, changed order, deletions and resets", ctx do
    row = %{"block" => ctx.block}
    ctx |> recover(ctx.page, row) |> Repo.update!()
    {:ok, page} = Brando.Blueprint.EntryQuery.get(Page, ctx.page.id)
    gallery = ref(page, "collection").gallery
    [first, video, last] = gallery.gallery_objects
    counts = asset_counts()
    row = Params.snapshot(hd(page.entry_blocks))

    row =
      update_in(row, ["block", "refs"], fn refs ->
        Enum.map(refs, fn
          %{"name" => "photo"} = ref ->
            Map.put(ref, "image_id", nil)

          %{"name" => "clip"} = ref ->
            Map.put(ref, "video_id", nil)

          %{"name" => "collection"} = ref ->
            put_in(ref, ["gallery", "gallery_objects"], [
              Params.snapshot(last) |> Map.put("sequence", 0),
              Params.snapshot(video) |> Map.put("sequence", 1)
            ])
        end)
      end)

    row =
      update_in(
        row,
        ["block", "vars"],
        &Enum.map(&1, fn var -> Map.merge(var, %{"image_id" => nil, "video_id" => nil, "file_id" => nil}) end)
      )

    ctx |> recover(page, row) |> Repo.update!()
    {:ok, recovered} = Brando.Blueprint.EntryQuery.get(Page, page.id)
    assert ref(recovered, "collection").gallery.id == gallery.id
    assert Enum.map(ref(recovered, "collection").gallery.gallery_objects, & &1.id) == [last.id, video.id]
    assert Repo.get(Brando.Galleries.GalleryObject, first.id) == nil
    assert ref(recovered, "photo").image_id == nil
    assert ref(recovered, "clip").video_id == nil
    assert Enum.all?(block(recovered).vars, &(is_nil(&1.image_id) && is_nil(&1.video_id) && is_nil(&1.file_id)))
    assert asset_counts() == counts
  end

  test "put_assoc captures selection and removal as library FKs for every media type", ctx do
    for {field, asset} <- [image: hd(ctx.images), video: ctx.video, file: ctx.asset_file] do
      fk = :"#{field}_id"
      empty = struct(Brando.Content.Ref, %{field => nil})
      selected = empty |> Changeset.change() |> Changeset.put_assoc(field, asset) |> Params.snapshot()
      assert selected[to_string(fk)] == asset.id
      refute Map.has_key?(selected, to_string(field))
      loaded = struct(Brando.Content.Ref, %{field => asset, fk => asset.id})
      cleared = loaded |> Changeset.change() |> Changeset.put_assoc(field, nil) |> Params.snapshot()
      assert cleared[to_string(fk)] == nil
    end
  end
end
