defmodule BrandoAdmin.Components.Form.ImageDrawerCopyTest do
  # "Save as new copy" in the image editor opened from an image field's
  # drawer or from the picker: the editor's `image_editor_save`, then its
  # export uploaded through the form's `image_editor_upload`. The copy goes
  # to the field the editor was opened for, as that field was when the copy
  # started.
  use Brando.LiveCase
  use Gettext, backend: Brando.Gettext

  alias Brando.Images.Focal
  alias Brando.SyncTest
  alias BrandoAdmin.Components.Form

  @form "#article_form_form"
  @sample Path.expand("../../../fixtures/sample.jpg", __DIR__)
  @cover_target Brando.Assets.ConfigTarget.serialize({"image", SyncTest.Article, :cover})

  setup %{conn: conn, current_user: user} do
    stored = image(user)
    gallery = Repo.insert!(%Brando.Galleries.Gallery{config_target: "default"})
    Repo.insert!(%Brando.Galleries.GalleryObject{gallery_id: gallery.id, image_id: stored.id, sequence: 0})

    {:ok, article} =
      SyncTest.create_article(%{title: "Media", slug: "media", language: "en", status: "published"}, user)

    article =
      article
      |> Ecto.Changeset.change(cover_id: stored.id, photos_id: gallery.id)
      |> Repo.update!()

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/media", "article_form")
    {:ok, view: view, stored: stored}
  end

  defp image(user, attrs \\ []) do
    Factory.insert(
      :image,
      [creator: user, focal: %Focal{x: 50, y: 50}, status: :processed, config_target: "default"] ++ attrs
    )
  end

  defp send_form(view, message) do
    Phoenix.LiveView.send_update(view.pid, Form, [id: "article_form"] ++ message)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  # The cover field's drawer opening on `image` (`Input.Image` "open_image")
  defp open_cover_drawer(view, image) do
    send_form(view,
      action: :update_edit_image,
      edit_image: %{id: image.id, path: [], field: :cover, relation_field: nil, schema: SyncTest.Article, image: image}
    )
  end

  # Done, ×, the backdrop and Escape all submit the drawer's form
  defp close_drawer(view), do: form_hook(view, "save_image", %{"image" => %{}})

  defp form_hook(view, event, params),
    do: view |> with_target(cid_of(view, "#article_form-el")) |> render_hook(event, params)

  # The editor's "Save as new copy": its save event, then the upload of its export
  defp start_copy(view, focal \\ %{"focal_x" => 40, "focal_y" => 60, "focal_mode" => "center"}) do
    form_hook(view, "image_editor_save", Map.merge(%{"mode" => "new_copy", "config_target" => @cover_target}, focal))
  end

  defp upload_copy(view) do
    view
    |> file_input(@form, :image_editor_upload, [%{name: "copy.jpg", content: File.read!(@sample), type: "image/jpeg"}])
    |> render_upload("copy.jpg")

    Brando.Images.Image |> Ecto.Query.last(:id) |> Repo.one!()
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "article_form")).assigns
  end

  defp cover_id(view), do: Ecto.Changeset.get_field(form_assigns(view).form.source, :cover_id)

  defp gallery_images(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(#{@form} input[name^="article[photos][gallery_objects]"][name$="[image_id]"]))
    |> Floki.attribute("value")
  end

  # An image picked from the library keeps the target it was uploaded for,
  # here another field's. Its copy is made for this field, with this field's
  # sizes, and the editor shows this field's cuts.
  test "the drawer's editor makes its copy for the field", %{view: view, current_user: user} do
    image = image(user, config_target: "image:Brando.Pages.Fragment:cover")
    open_cover_drawer(view, image)

    form_hook(view, "open_image_editor", %{"image_id" => image.id})

    assert_push_event(view, "b:image_editor:init", payload)
    assert payload.image_id == image.id
    assert payload.config_target == @cover_target
    assert payload.crop_groups == [%{ratio: 1.0, label: "1:1", size_keys: ["medium"]}]
  end

  # As the Figma import places it: an untouched copy is cut where the
  # original is, not around the centre. The field takes the copy as it takes
  # a drawer upload: the browser is told and the image is followed while it
  # processes.
  test "a copy of an image in position mode takes the field with the point and mode", %{view: view, stored: stored} do
    open_cover_drawer(view, stored)
    start_copy(view, %{"focal_x" => 75, "focal_y" => 0, "focal_mode" => "position"})
    copy = upload_copy(view)

    assert copy.id != stored.id
    assert cover_id(view) == copy.id
    assert form_assigns(view).edit_image.image.id == copy.id
    assert Brando.Images.get_image!(copy.id).focal == %Focal{x: 75, y: 0, mode: :position}
    copy_id = copy.id
    assert_push_event(view, "b:validate", %{target: "article[cover_id]", value: ^copy_id})
  end

  test "a copy from the picker's editor takes the drawer's field", %{view: view, stored: stored, current_user: user} do
    picked = image(user)
    open_cover_drawer(view, stored)
    send_form(view, action: :open_image_editor_from_picker, image: picked)
    start_copy(view, %{"focal_x" => 20, "focal_y" => 30, "focal_mode" => "center"})
    copy = upload_copy(view)

    assert cover_id(view) == copy.id
    assert Brando.Images.get_image!(copy.id).focal == %Focal{x: 20, y: 30, mode: :center}
  end

  # The cover's drawer was closed, and the picker opened since is a block's,
  # a var's or a gallery's: the editor is not the field's. Its copy stays in
  # the library, and the form's save is not held for a drawer that is shut.
  test "a copy from the picker's editor after the field's drawer closed", %{
    view: view,
    stored: stored,
    current_user: user
  } do
    picked = image(user)
    open_cover_drawer(view, stored)
    close_drawer(view)

    send_form(view, action: :open_image_editor_from_picker, image: picked)

    assert_push_event(view, "b:image_editor:init", payload)
    assert payload.config_target == picked.config_target
    refute form_assigns(view).editing_image?

    start_copy(view, %{
      "config_target" => picked.config_target,
      "focal_x" => 40,
      "focal_y" => 60,
      "focal_mode" => "center"
    })

    copy = upload_copy(view)

    assert copy.id not in [stored.id, picked.id]
    assert cover_id(view) == stored.id
  end

  # "Save" (replace) in the picker's editor changes the library image; no
  # field of the entry holds it, and the entry is left alone
  test "a replace from the picker's editor leaves the entry alone", %{view: view, current_user: user} do
    name = "replace-#{System.unique_integer([:positive])}.jpg"
    picked = image(user, path: "image/#{name}")
    original = Path.join(Brando.Tenant.Storage.current_media_root(), picked.path)
    File.mkdir_p!(Path.dirname(original))
    on_exit(fn -> File.rm(original) end)
    File.cp!(@sample, original)

    send_form(view, action: :open_image_editor_from_picker, image: picked)
    entry = form_assigns(view).entry

    form_hook(view, "image_editor_save", %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70})

    assert form_assigns(view).entry == entry
    assert Repo.get!(Brando.Images.Image, picked.id).focal.x == 30
  end

  # A gallery opened the editor before: its copy went back to the gallery.
  # The picker's editor opened since is not the gallery's, and its copy
  # replaces nothing there.
  test "a copy from the picker's editor after a gallery's editor", %{view: view, stored: stored, current_user: user} do
    picked = image(user)

    view
    |> with_target(cid_of(view, "#article_photos-gallery-view"))
    |> render_hook("open_image_editor", %{"image_id" => to_string(stored.id)})

    send_form(view, action: :open_image_editor_from_picker, image: picked)
    start_copy(view)
    copy = upload_copy(view)

    assert copy.id not in [stored.id, picked.id]
    assert gallery_images(view) == [to_string(stored.id)]
    assert cover_id(view) == stored.id
  end

  # The field takes another image while the copy uploads: the copy stays in
  # the library.
  test "a copy that lands after the field took another image", %{view: view, stored: stored, current_user: user} do
    picked = image(user)
    open_cover_drawer(view, stored)
    start_copy(view)
    send_form(view, action: :update_edit_image, image: picked)
    assert cover_id(view) == picked.id

    copy = upload_copy(view)

    assert copy.id != picked.id
    assert cover_id(view) == picked.id
    assert form_assigns(view).edit_image.image.id == picked.id
  end

  # A field whose own target is not a Blueprint image asset: the editor
  # opens with the image's own target and cuts.
  test "the drawer's editor for a field without an image config", %{view: view, stored: stored} do
    send_form(view,
      action: :update_edit_image,
      edit_image: %{id: stored.id, path: [], field: :title, relation_field: nil, schema: SyncTest.Article, image: stored}
    )

    form_hook(view, "open_image_editor", %{"image_id" => stored.id})

    assert_push_event(view, "b:image_editor:init", payload)
    assert payload.config_target == stored.config_target
  end

  # The field refuses the copy: the editor is told it is in the library,
  # not that it was made as asked.
  test "a copy refused by its field is reported as left in the library", %{
    view: view,
    stored: stored,
    current_user: user
  } do
    picked = image(user)
    open_cover_drawer(view, stored)
    start_copy(view)
    send_form(view, action: :update_edit_image, image: picked)
    Brando.endpoint().subscribe("user:#{user.id}")

    upload_copy(view)

    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}}
    refute message == gettext("New image created.")
  end

  # Another field's drawer opened while the copy uploads: the copy goes to
  # the field it was made in, and the open drawer keeps its own field.
  test "a copy that lands while another field's drawer is open", %{view: view, stored: stored, current_user: user} do
    portrait = image(user)
    open_cover_drawer(view, stored)
    start_copy(view)

    send_form(view,
      action: :update_edit_image,
      edit_image: %{
        id: portrait.id,
        path: [:author],
        field: :portrait,
        relation_field: nil,
        schema: SyncTest.ArticleAuthor,
        image: portrait
      }
    )

    copy = upload_copy(view)

    assert cover_id(view) == copy.id
    assert %{field: :portrait, path: [:author], image: %{id: portrait_id}} = form_assigns(view).edit_image
    assert portrait_id == portrait.id
    assert form_assigns(view).image_changeset.data.id == portrait.id
  end
end
