defmodule BrandoAdmin.Components.Form.Input.GalleryTest do
  # Regression coverage for D4 and D5 in the form audit.
  #
  # D4 — the component addressed the entry form as
  # `"#{changeset.data.__struct__.__naming__().singular}_form"`. That changeset
  # belongs to whatever schema OWNS the gallery field, so for a gallery on a
  # nested (subform) record it named a component that does not exist and every
  # picker selection silently went nowhere. It also shipped a replacement
  # changeset for that nested record — which, had the id ever matched, would
  # have overwritten the entry's changeset with a subrecord's. The upload path
  # never had either problem because it delivers `path` + gallery instead.
  #
  # D5 — `gallery_objects` / `selected_images` / `selected_videos` were cached
  # with `assign_new`, so a gallery mutated anywhere else (an upload delivered
  # to the entry form, a revision restore) never reached the UI. They now
  # re-derive from the changeset every update, carrying previously-loaded
  # `:image` / `:video` across by id so the thumbnails survive the round trip.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1, to_form: 2]

  alias Brando.Factory
  alias Brando.Galleries
  alias Brando.Galleries.GalleryObject
  alias Brando.MigrationTest.ProjectUpdate1
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Gallery
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    {:ok, user: user, image: Factory.insert(:image, creator: user)}
  end

  defp gallery_socket(form, path, extra) do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:field, form[:photos])
      |> Component.assign(:path, path)
      |> Component.assign(:gallery_objects, [])
      |> Component.assign(:selected_images, [])
      |> Component.assign(:selected_videos, [])
      |> Component.assign(extra)

    %{socket | assigns: Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})}
  end

  describe "D4 — picker writes reach the entry form" do
    test "a top-level gallery ships path + key to the entry form", ctx do
      form = to_form(Changeset.change(%ProjectUpdate1{}))

      socket = gallery_socket(form, [], %{current_user: ctx.user, form_id: "project_form"})

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "project_form"}, assigns}}
      assert assigns.action == :put_gallery
      assert assigns.path == []
      assert assigns.key == :photos
      assert [%{image_id: image_id}] = assigns.gallery.gallery_objects
      assert image_id == ctx.image.id
    end

    test "a NESTED gallery addresses the entry form, not its own schema's", ctx do
      # The gallery is owned by a subrecord rendered inside a Page's form.
      # `Form.input/1` threads the entry form component's id down as `form_id`;
      # before the fix the component ignored it and derived one from its own
      # changeset's struct instead, naming a component that is not mounted.
      form = to_form(Changeset.change(%ProjectUpdate1{}), as: "page[projects][0]")

      socket =
        gallery_socket(form, [:projects, 0], %{current_user: ctx.user, form_id: "page_form"})

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "page_form"}, assigns}}
      assert assigns.path == [:projects, 0]
      assert assigns.key == :photos
    end

    test "falls back to the form name's root when no form_id was threaded", ctx do
      # A gallery rendered outside the standard field pipeline still has to land
      # somewhere real. The ROOT of a nested form name is the entry's own name —
      # never the owning schema's.
      form = to_form(Changeset.change(%ProjectUpdate1{}), as: "page[projects][0]")

      socket = gallery_socket(form, [:projects, 0], %{current_user: ctx.user})

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "page_form"}, _assigns}}
    end

    test "removing media reaches the same target", ctx do
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: []
      }

      form = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}), as: "page[projects][0]")

      socket =
        gallery_socket(form, [:projects, 0], %{
          current_user: ctx.user,
          form_id: "page_form",
          gallery_objects: [%GalleryObject{image_id: ctx.image.id}],
          selected_images: [ctx.image.id]
        })

      assert {:noreply, _socket} =
               Gallery.handle_event("select_image", %{"id" => to_string(ctx.image.id)}, socket)

      assert_receive {:phoenix, :send_update, {{Form, "page_form"}, assigns}}
      assert assigns.action == :put_gallery
      assert assigns.gallery.gallery_objects == []
    end
  end

  describe "D5 — merge_loaded_media/2" do
    test "recovery loads uncached images and videos from their FKs", ctx do
      video = Factory.insert(:video)
      objects = [%GalleryObject{image_id: ctx.image.id}, %GalleryObject{video_id: video.id}]

      [image_object, video_object] =
        BrandoAdmin.Components.Form.Input.Gallery.Media.load_missing(objects)

      assert image_object.image.id == ctx.image.id
      assert video_object.video.id == video.id
      assert image_object.id == nil
      assert video_object.id == nil
    end

    test "a recovered replacement does not reuse the saved object's old image", ctx do
      replacement = Factory.insert(:image)
      object = %GalleryObject{image_id: replacement.id, image: ctx.image}

      assert [%{image: image}] = BrandoAdmin.Components.Form.Input.Gallery.Media.load_missing([object])
      assert image.id == replacement.id
    end

    test "keeps an object that already carries its loaded media" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1, path: "a.jpg"}}

      assert [^loaded] = Galleries.merge_loaded_media([loaded], [])
    end

    test "borrows loaded media from the previous list by image id" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1, path: "a.jpg"}}
      slim = %GalleryObject{image_id: 1}

      assert [%{image: %{path: "a.jpg"}}] = Galleries.merge_loaded_media([slim], [loaded])
    end

    test "borrows loaded media by video id too" do
      loaded = %GalleryObject{video_id: 9, video: %Brando.Videos.Video{id: 9}}
      slim = %GalleryObject{video_id: 9}

      assert [%{video: %Brando.Videos.Video{id: 9}}] =
               Galleries.merge_loaded_media([slim], [loaded])
    end

    test "does not borrow across different media" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1}}
      slim = %GalleryObject{image_id: 2}

      assert [%{image_id: 2, image: %Ecto.Association.NotLoaded{}}] =
               Galleries.merge_loaded_media([slim], [loaded])
    end

    test "the changeset decides membership — a removed object does not linger" do
      loaded = %GalleryObject{image_id: 1, image: %Brando.Images.Image{id: 1}}

      assert Galleries.merge_loaded_media([], [loaded]) == []
    end
  end

  describe "D5 — the component tracks the changeset" do
    test "an externally added object shows up on the next update", ctx do
      empty = to_form(Changeset.change(%ProjectUpdate1{}))
      socket = gallery_socket(empty, [], %{current_user: ctx.user})

      # Something else (an upload delivery, a revision restore) writes the
      # gallery into the entry changeset. The component is only handed the new
      # field — with `assign_new` it kept showing the empty list forever.
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: [
          %GalleryObject{image_id: ctx.image.id, image: ctx.image}
        ]
      }

      mutated = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}))

      assert {:ok, socket} =
               Gallery.update(%{field: mutated[:photos], current_user: ctx.user, opts: []}, socket)

      assert [%{image_id: image_id}] = socket.assigns.gallery_objects
      assert image_id == ctx.image.id
      assert socket.assigns.selected_images == [ctx.image.id]
    end

    test "a slimmed object keeps the media the component had already loaded", ctx do
      # This is what makes re-deriving safe: writing the list back through
      # `put_assoc` strips the preloaded :image, so deriving alone would blank
      # every thumbnail.
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
        gallery_objects: [%GalleryObject{image_id: ctx.image.id}]
      }

      form = to_form(Changeset.change(%ProjectUpdate1{photos: gallery}))

      socket =
        gallery_socket(form, [], %{
          current_user: ctx.user,
          gallery_objects: [%GalleryObject{image_id: ctx.image.id, image: ctx.image}]
        })

      assert {:ok, socket} =
               Gallery.update(%{field: form[:photos], current_user: ctx.user, opts: []}, socket)

      assert [%{image: %Brando.Images.Image{}}] = socket.assigns.gallery_objects
    end
  end

  describe "D5 review follow-up — merge picks the FRESHER media, not the loaded one" do
    # B1 from the Phase 2 review. `merge_loaded_media/2` originally kept the
    # changeset's object whenever its association happened to be loaded. But the
    # editor refreshes an image in place when Oban finishes processing it, and
    # that refresh only ever reaches the cached list — so a stale-but-loaded
    # changeset copy silently reverted a just-processed image on the next
    # unrelated update. That is a regression the D5 fix introduced: the
    # `assign_new` it replaced could not lose a refresh, because it never
    # re-read.
    defp at(seconds) do
      NaiveDateTime.add(~N[2026-01-01 00:00:00], seconds, :second)
    end

    defp object_with_image(image) do
      %GalleryObject{image_id: image.id, image: image}
    end

    test "a freshly-processed cached image survives a stale changeset copy" do
      stale = %Brando.Images.Image{id: 1, status: :unprocessed, updated_at: at(0)}
      fresh = %Brando.Images.Image{id: 1, status: :processed, updated_at: at(60)}

      assert [%{image: kept}] =
               Galleries.merge_loaded_media(
                 [object_with_image(stale)],
                 [object_with_image(fresh)]
               )

      assert kept.status == :processed
    end

    test "a fresher changeset copy still wins over the cache" do
      # The mirror case: after something reloads the entry, the changeset holds
      # the newer copy and must not be overridden by a stale cache.
      cached = %Brando.Images.Image{id: 1, status: :unprocessed, updated_at: at(0)}
      reloaded = %Brando.Images.Image{id: 1, status: :processed, updated_at: at(60)}

      assert [%{image: kept}] =
               Galleries.merge_loaded_media(
                 [object_with_image(reloaded)],
                 [object_with_image(cached)]
               )

      assert kept.status == :processed
    end

    test "a tie keeps the cached copy — timestamps are only second-precise" do
      # The e2e regression (`tests/projects/projects.spec.js`). `updated_at` is
      # `Ecto.Schema.timestamps()`' default `:naive_datetime`, so upload →
      # process → refresh routinely lands inside one second and the refreshed
      # image compares EQUAL to the changeset's snapshot of it. Requiring a
      # strict `:gt` threw the refresh away: uploading two images to a gallery
      # reverted the first to `:unprocessed` the moment the second was
      # delivered, and its thumbnail stayed a spinner instead of an `<img>`.
      snapshot = %Brando.Images.Image{id: 1, status: :unprocessed, updated_at: at(0)}
      refreshed = %Brando.Images.Image{id: 1, status: :processed, updated_at: at(0)}

      assert [%{image: kept}] =
               Galleries.merge_loaded_media(
                 [object_with_image(snapshot)],
                 [object_with_image(refreshed)]
               )

      assert kept.status == :processed
    end

    test "a tie writes back an equal term, so it still cannot churn the assign" do
      # The property the old strict-`:gt` tie-break was protecting. It survives
      # the change: when both sides hold the same media, keeping the cached one
      # yields a term equal to the object that went in.
      image = %Brando.Images.Image{id: 1, title: "same", updated_at: at(0)}
      object = object_with_image(image)

      assert Galleries.merge_loaded_media([object], [object_with_image(image)]) == [object]
    end

    test "an unloaded changeset object still borrows the cached media" do
      # The original D5 behaviour, which must not regress.
      image = %Brando.Images.Image{id: 1, path: "a.jpg", updated_at: at(0)}

      assert [%{image: %{path: "a.jpg"}}] =
               Galleries.merge_loaded_media(
                 [%GalleryObject{image_id: 1}],
                 [object_with_image(image)]
               )
    end
  end

  describe "D5 review follow-up — delivery cannot duplicate an object" do
    # B2 from the Phase 2 review. Upload delivery writes `gallery_objects`
    # directly AND updates the entry changeset, which reaches this component
    # again through assign_value/1. Two writers, one event, no guaranteed
    # ordering — a plain `++` duplicated the object when the direct write
    # landed second.
    test "append_unique_media/2 is idempotent per media id" do
      object = %GalleryObject{image_id: 7}

      assert Galleries.append_unique_media([], object) == [object]
      assert Galleries.append_unique_media([object], object) == [object]
      assert Galleries.append_unique_media([object], %GalleryObject{image_id: 7}) == [object]
    end

    test "append_unique_media/2 still appends a genuinely different object" do
      first = %GalleryObject{image_id: 7}
      second = %GalleryObject{image_id: 8}

      assert Galleries.append_unique_media([first], second) == [first, second]
    end

    test "videos dedupe on their own id, not against images" do
      image = %GalleryObject{image_id: 7}
      video = %GalleryObject{video_id: 7}

      assert Galleries.append_unique_media([image], video) == [image, video]
      assert Galleries.append_unique_media([video], %GalleryObject{video_id: 7}) == [video]
    end

    test "the delivery clause does not duplicate when it runs twice", ctx do
      # Drives the real update/2 clause the review flagged.
      form = to_form(Changeset.change(%ProjectUpdate1{}))
      new_image = %GalleryObject{image_id: ctx.image.id, image: ctx.image}

      socket = gallery_socket(form, [], %{current_user: ctx.user})

      assert {:ok, socket} =
               Gallery.update(%{new_image: new_image, selected_images: [ctx.image.id]}, socket)

      assert {:ok, socket} =
               Gallery.update(%{new_image: new_image, selected_images: [ctx.image.id]}, socket)

      assert length(socket.assigns.gallery_objects) == 1
    end
  end

  describe "put_gallery_at/4 — unsaved objects have no identity to match on" do
    # `gallery_at/3` reads the APPLIED gallery, so objects the editor added but
    # has not saved sit in `data` with `id: nil`. `put_assoc` keys that data by
    # primary key to match the incoming params against it
    # (`Ecto.Changeset.Relation.process_current/3`), and every nil-id object
    # keys on `[nil]` — so all but the last shadow each other and each nil-id
    # param is then matched against whichever object happened to survive.
    #
    # It came out right only because `slim_gallery_object/1` pins every writable
    # field, so the mismatched base contributed nothing. That is an accident of
    # the param shape, not a guarantee, and Ecto says so out loud.
    defp deliver_gallery_image(socket, image) do
      {:ok, socket} =
        Form.update(
          %{
            event: "entry_field_upload_complete",
            asset_type: :gallery,
            field: :photos,
            path: [],
            asset: image,
            component_id: "project_photos"
          },
          socket
        )

      socket
    end

    defp entry_form_socket(ctx) do
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:form, to_form(Changeset.change(%ProjectUpdate1{})))
      |> Component.assign(:schema, ProjectUpdate1)
      |> Component.assign(:singular, "project")
      |> Component.assign(:current_user, ctx.user)
      |> Component.assign(:processing_images, [])
    end

    test "a third delivery does not log a duplicate-primary-key warning", ctx do
      # The test env pins `config :logger, level: :error`, which drops Ecto's
      # warning at the primary filter before any capture handler sees it — so
      # this assertion is vacuous unless the level is lowered for its duration.
      previous_level = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous_level) end)

      second = Factory.insert(:image, creator: ctx.user)
      third = Factory.insert(:image, creator: ctx.user)

      socket =
        ctx
        |> entry_form_socket()
        |> deliver_gallery_image(ctx.image)
        |> deliver_gallery_image(second)

      # Two unsaved objects are now in the applied gallery. The next write is
      # what hands Ecto a `current` list it cannot key.
      {socket, log} =
        ExUnit.CaptureLog.with_log(fn -> deliver_gallery_image(socket, third) end)

      refute log =~ "duplicate primary keys"

      gallery = Changeset.get_field(socket.assigns.form.source, :photos)

      assert Enum.map(gallery.gallery_objects, & &1.image_id) ==
               [ctx.image.id, second.id, third.id]
    end

    test "every delivered object is a distinct insert", ctx do
      # No unit-test schema owns a migrated gallery FK, so the save round trip
      # lives in e2e (`tests/projects/projects.spec.js` reopens the entry and
      # asserts three objects). What is assertable here is the shape that
      # decides it: three separate inserts, none of them matched onto another
      # object's struct.
      second = Factory.insert(:image, creator: ctx.user)
      third = Factory.insert(:image, creator: ctx.user)

      socket =
        ctx
        |> entry_form_socket()
        |> deliver_gallery_image(ctx.image)
        |> deliver_gallery_image(second)
        |> deliver_gallery_image(third)

      objects = Changeset.get_change(socket.assigns.form.source, :photos).changes.gallery_objects

      assert Enum.map(objects, & &1.action) == [:insert, :insert, :insert]

      assert Enum.map(objects, &Changeset.get_field(&1, :image_id)) ==
               [ctx.image.id, second.id, third.id]

      # Each insert must build on a blank struct, not on a sibling's data —
      # that is what the duplicate-primary-key warning was reporting.
      assert Enum.all?(objects, &is_nil(&1.data.image_id))
    end

    test "an object that already has an id still matches instead of duplicating", ctx do
      # The other half of the invariant: dropping unsaved objects from the base
      # must not stop persisted ones from being matched and updated in place.
      persisted =
        Ecto.put_meta(%GalleryObject{id: 42, image_id: ctx.image.id, sequence: 0}, state: :loaded)

      gallery =
        Ecto.put_meta(
          %Brando.Galleries.Gallery{
            id: 7,
            config_target: "gallery:Brando.MigrationTest.ProjectUpdate1:photos",
            gallery_objects: [persisted]
          },
          state: :loaded
        )

      socket =
        %Phoenix.LiveView.Socket{}
        |> Component.assign(:form, to_form(Changeset.change(%ProjectUpdate1{photos: gallery})))
        |> Component.assign(:schema, ProjectUpdate1)
        |> Component.assign(:singular, "project")
        |> Component.assign(:current_user, ctx.user)
        |> Component.assign(:processing_images, [])

      second = Factory.insert(:image, creator: ctx.user)
      socket = deliver_gallery_image(socket, second)

      objects = Changeset.get_change(socket.assigns.form.source, :photos).changes.gallery_objects

      assert [%{action: :update, data: %{id: 42}}, %{action: :insert}] = objects
    end
  end
end
