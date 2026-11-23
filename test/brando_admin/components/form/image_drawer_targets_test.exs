defmodule BrandoAdmin.Components.Form.ImageDrawerTargetsTest do
  # What the image drawer and the picker's "Edit image" act on: an upload
  # goes to the field it was started for, and the editor works on the image
  # it was opened for, never on a field, block or gallery that did not open
  # it.
  use Brando.LiveCase

  alias Brando.Images.Focal
  alias Brando.SyncTest
  alias BrandoAdmin.Components.Form

  @sample Path.expand("../../../fixtures/sample.jpg", __DIR__)

  setup %{current_user: user} do
    stored = image(user)
    gallery = Repo.insert!(%Brando.Galleries.Gallery{config_target: "default"})
    Repo.insert!(%Brando.Galleries.GalleryObject{gallery_id: gallery.id, image_id: stored.id, sequence: 0})

    {:ok, article} =
      SyncTest.create_article(%{title: "Media", slug: "media", language: "en", status: "published"}, user)

    article =
      article
      |> Ecto.Changeset.change(cover_id: stored.id, photos_id: gallery.id)
      |> Repo.update!()

    {:ok, article: article, stored: stored}
  end

  defp open(conn, article, form), do: live_form(conn, "/admin/articles/update/#{article.id}/#{form}", "article_form")

  defp image(user, attrs \\ []) do
    Factory.insert(
      :image,
      [creator: user, focal: %Focal{x: 50, y: 50}, status: :processed, config_target: "default"] ++ attrs
    )
  end

  # An image with its original on disk, for the editor's "Save" (replace)
  defp image_on_disk(user) do
    name = "targets-#{System.unique_integer([:positive])}.jpg"
    image = image(user, path: "image/#{name}")
    original = Path.join(Brando.Tenant.Storage.current_media_root(), image.path)
    File.mkdir_p!(Path.dirname(original))
    on_exit(fn -> File.rm(original) end)
    File.cp!(@sample, original)
    image
  end

  defp send_form(view, message) do
    Phoenix.LiveView.send_update(view.pid, Form, [id: "article_form"] ++ message)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp form_hook(view, event, params),
    do: view |> with_target(cid_of(view, "#article_form-el")) |> render_hook(event, params)

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "article_form")).assigns
  end

  defp field(view, key), do: Ecto.Changeset.get_field(form_assigns(view).form.source, key)

  # `Input.Image` "open_image"
  defp open_drawer(view, field, path, schema, image) do
    send_form(view,
      action: :update_edit_image,
      edit_image: %{id: image.id, path: path, field: field, relation_field: nil, schema: schema, image: image}
    )
  end

  defp open_cover_drawer(view, image), do: open_drawer(view, :cover, [], SyncTest.Article, image)

  defp open_portrait_drawer(view, image), do: open_drawer(view, :portrait, [:author], SyncTest.ArticleAuthor, image)

  # Done, ×, the backdrop and Escape all submit the drawer's form
  defp close_drawer(view), do: form_hook(view, "save_image", %{"image" => %{}})

  # The UploadManager's delivery of an upload started in the cover's drawer
  # while it showed `shown` (`LiveView.Form.Hooks`)
  defp deliver_cover_upload(view, shown, uploaded) do
    send_form(view,
      event: "entry_field_upload_complete",
      asset_type: :image,
      expected_asset_id: to_string(shown.id),
      field: :cover,
      path: [],
      asset: uploaded
    )
  end

  describe "a drawer upload" do
    test "that lands while another field's drawer is open goes to its own field", %{
      conn: conn,
      article: article,
      stored: stored,
      current_user: user
    } do
      [uploaded, portrait] = [image(user), image(user)]
      Repo.insert!(%SyncTest.ArticleAuthor{article_id: article.id, name: "Author", portrait_id: portrait.id})
      {view, _html} = open(conn, article, :media)

      open_cover_drawer(view, stored)
      close_drawer(view)
      open_portrait_drawer(view, portrait)

      deliver_cover_upload(view, stored, uploaded)

      assert field(view, :cover_id) == uploaded.id
      assert %{field: :portrait, path: [:author], id: portrait_id} = form_assigns(view).edit_image
      assert portrait_id == portrait.id
      assert form_assigns(view).image_changeset.data.id == portrait.id

      close_drawer(view)

      assert field(view, :cover_id) == uploaded.id
      assert field(view, :author).portrait_id == portrait.id
    end

    test "that lands while its own field's drawer is open shows in it", %{
      conn: conn,
      article: article,
      stored: stored,
      current_user: user
    } do
      uploaded = image(user)
      {view, _html} = open(conn, article, :media)

      open_cover_drawer(view, stored)
      deliver_cover_upload(view, stored, uploaded)

      assert field(view, :cover_id) == uploaded.id
      assert %{field: :cover, id: uploaded_id} = form_assigns(view).edit_image
      assert uploaded_id == uploaded.id
      assert form_assigns(view).image_changeset.data.id == uploaded.id
    end
  end

  # The form shows an empty author row on an article without one
  describe "an image in a one-to-one subform with no row yet" do
    setup %{current_user: user} do
      {:ok, article} =
        SyncTest.create_article(%{title: "No author", slug: "no-author", language: "en", status: "published"}, user)

      {:ok, article: article}
    end

    test "uploaded starts the row", %{conn: conn, article: article, current_user: user} do
      portrait = image(user)
      {view, _html} = open(conn, article, :media)

      send_form(view,
        event: "entry_field_upload_complete",
        asset_type: :image,
        field: :portrait,
        path: [:author],
        asset: portrait
      )

      assert field(view, :author).portrait_id == portrait.id
    end

    test "is kept by the drawer's Done", %{conn: conn, article: article, current_user: user} do
      portrait = image(user)
      {view, _html} = open(conn, article, :media)

      open_portrait_drawer(view, portrait)
      close_drawer(view)

      assert field(view, :author).portrait_id == portrait.id
      refute form_assigns(view).editing_image?
    end

    test "is not started by the drawer's Remove", %{conn: conn, article: article, current_user: user} do
      {view, _html} = open(conn, article, :media)
      open_portrait_drawer(view, image(user))

      form_hook(view, "reset_image_field", %{})

      assert field(view, :author) == nil
    end

    test "on a new entry is started by an upload and kept by Done", %{conn: conn, current_user: user} do
      portrait = image(user)
      {view, _html} = live_form(conn, "/admin/articles/create/media", "article_form")

      send_form(view,
        event: "entry_field_upload_complete",
        asset_type: :image,
        field: :portrait,
        path: [:author],
        asset: portrait
      )

      open_portrait_drawer(view, portrait)
      close_drawer(view)

      assert field(view, :author).portrait_id == portrait.id
    end
  end

  describe "the picker's \"Edit image\"" do
    # A gallery's editor left its keys in `edit_image`. The picker's editor
    # opened since is not the gallery's: its "Save" changes the library image
    # and sends the gallery nothing.
    test "after a gallery's editor saves for no gallery", %{conn: conn, article: article, stored: stored} = ctx do
      picked = image_on_disk(ctx.current_user)
      {view, _html} = open(conn, article, :media)

      view
      |> with_target(cid_of(view, "#article_photos-gallery-view"))
      |> render_hook("open_image_editor", %{"image_id" => to_string(stored.id)})

      send_form(view, action: :open_image_editor_from_picker, image: picked)

      # Processing runs inline and clears the registration at once: watch
      # the LiveView's mailbox for it instead
      :erlang.trace(view.pid, true, [:receive])
      form_hook(view, "image_editor_save", %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70})
      _ = :sys.get_state(view.pid)
      :erlang.trace(view.pid, false, [:receive])

      assert Repo.get!(Brando.Images.Image, picked.id).focal.x == 30
      refute_received {:trace, _, :receive, {:register_pending_block_image, _, _}}
    end

    # A locked field's open drawer keeps its image. The editor opens on the
    # picked image, for no field, rather than showing the image it last had.
    test "in a locked field's drawer edits the picked image", %{conn: conn, article: article, stored: stored} = ctx do
      picked = image_on_disk(ctx.current_user)
      {view, _html} = open(conn, article, :locked_media)
      open_cover_drawer(view, stored)

      send_form(view, action: :open_image_editor_from_picker, image: picked)

      assert_push_event(view, "b:image_editor:init", payload)
      assert payload.image_id == picked.id
      assert payload.config_target == picked.config_target

      form_hook(view, "image_editor_save", %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70})

      assert Repo.get!(Brando.Images.Image, picked.id).focal.x == 30
      assert Repo.get!(Brando.Images.Image, stored.id).focal.x == 50

      close_drawer(view)

      assert field(view, :cover_id) == stored.id
      refute form_assigns(view).editing_image?
    end

    # The editor's Cancel tells the server nothing: the drawer still shows,
    # takes uploads for and saves the field's own image
    test "in a locked field's drawer leaves the drawer on the field's image",
         %{conn: conn, article: article, stored: stored} = ctx do
      picked = image(ctx.current_user)
      {view, _html} = open(conn, article, :locked_media)
      open_cover_drawer(view, stored)

      send_form(view, action: :open_image_editor_from_picker, image: picked)

      assert %{field: :cover, id: shown_id} = form_assigns(view).edit_image
      assert shown_id == stored.id
      assert form_assigns(view).image_changeset.data.id == stored.id
      assert has_element?(view, ~s(#image-drawer-form-preview[data-field="cover"][data-asset-id="#{stored.id}"]))

      form_hook(view, "save_image", %{"image" => %{"credits" => %{"en" => "Typed before"}}})

      assert Repo.get!(Brando.Images.Image, stored.id).credits["en"] == "Typed before"
      assert field(view, :cover_id) == stored.id
      refute form_assigns(view).editing_image?
    end

    test "in a locked field's drawer leaves its Remove to the locked field",
         %{conn: conn, article: article, stored: stored} = ctx do
      picked = image(ctx.current_user)
      {view, _html} = open(conn, article, :locked_media)
      open_cover_drawer(view, stored)
      send_form(view, action: :open_image_editor_from_picker, image: picked)

      form_hook(view, "reset_image_field", %{})

      assert field(view, :cover_id) == stored.id
      refute form_assigns(view).editing_image?
    end

    # The picked image is the editor's only while the picker opened it: the
    # next field drawer's "Edit image" saves for that field
    test "in a locked field's drawer is not the next drawer's editor",
         %{conn: conn, article: article, stored: stored} = ctx do
      [picked, portrait] = [image(ctx.current_user), image_on_disk(ctx.current_user)]
      Repo.insert!(%SyncTest.ArticleAuthor{article_id: article.id, name: "Author", portrait_id: portrait.id})
      {view, _html} = open(conn, article, :locked_media)
      open_cover_drawer(view, stored)
      send_form(view, action: :open_image_editor_from_picker, image: picked)
      close_drawer(view)

      open_portrait_drawer(view, portrait)
      form_hook(view, "open_image_editor", %{"image_id" => to_string(portrait.id)})
      form_hook(view, "image_editor_save", %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70})

      assert Repo.get!(Brando.Images.Image, portrait.id).focal.x == 30
      assert Repo.get!(Brando.Images.Image, picked.id).focal.x == 50
      assert form_assigns(view).edit_image.image.focal.x == 30
    end
  end

  # The editor's "Save" (replace) changes the image, never a locked field
  # (#3884): the field keeps its image and the form is not validated with it
  describe "the editor's Save in a locked field" do
    for {name, params} <- [
          refocus: %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70},
          crop: %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70, "crop_applied" => true}
        ] do
      test "from the drawer's own Edit image (#{name}) saves the image and leaves the field",
           %{conn: conn, article: article} = ctx do
        cover = image_on_disk(ctx.current_user)
        article = article |> Ecto.Changeset.change(cover_id: cover.id) |> Repo.update!()
        {view, _html} = open(conn, article, :locked_media)
        open_cover_drawer(view, cover)

        form_hook(view, "open_image_editor", %{"image_id" => to_string(cover.id)})
        form_hook(view, "image_editor_save", Map.put(unquote(Macro.escape(params)), "image_id", to_string(cover.id)))

        refute_push_event(view, "b:validate", _)
        assert field(view, :cover_id) == cover.id
        assert form_assigns(view).edit_image.image.id == cover.id
        if unquote(name) == :refocus, do: assert(Repo.get!(Brando.Images.Image, cover.id).focal.x == 30)
      end
    end

    # The picker's "Edit image" in the field's open drawer, then the field
    # locks: the parent's next render passes a user it is locked for
    test "after the field locked mid-edit saves the picked image and leaves the field",
         %{conn: conn, article: article, stored: stored, current_user: user} do
      picked = image_on_disk(user)
      {view, _html} = open(conn, article, :superuser_media)
      open_cover_drawer(view, stored)
      send_form(view, action: :open_image_editor_from_picker, image: picked)

      send_form(view, current_user: %{user | role: :editor})
      form_hook(view, "image_editor_save", %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70})

      assert Repo.get!(Brando.Images.Image, picked.id).focal.x == 30
      refute_push_event(view, "b:validate", _)
      assert form_assigns(view).entry.cover.id == stored.id
      assert field(view, :cover_id) == stored.id
    end

    # Closing the drawer saves the image it shows, the picked one
    test "after the field locked mid-edit, the drawer's Done leaves the field",
         %{conn: conn, article: article, stored: stored, current_user: user} do
      picked = image_on_disk(user)
      {view, _html} = open(conn, article, :superuser_media)
      open_cover_drawer(view, stored)
      send_form(view, action: :open_image_editor_from_picker, image: picked)
      send_form(view, current_user: %{user | role: :editor})
      form_hook(view, "image_editor_save", %{"mode" => "replace", "focal_x" => 30, "focal_y" => 70})

      form_hook(view, "save_image", %{"image" => %{"alt" => "Picked"}})

      assert %{"en" => "Picked"} = Repo.get!(Brando.Images.Image, picked.id).alt
      refute_push_event(view, "b:validate", _)
      assert form_assigns(view).entry.cover.id == stored.id
      assert field(view, :cover_id) == stored.id
      refute form_assigns(view).editing_image?
    end
  end

  # The image's own form opens the editor on itself (`Input.ImageFocal`).
  # Closing the editor tells the server nothing, so the form's save is not
  # held for a drawer.
  test "an image's own editor does not hold the image's save", %{conn: conn, current_user: user} do
    image = image(user, path: "images/own/a.jpg")
    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")

    view |> with_target(cid_of(view, "#image_form-el")) |> render_hook("open_own_image_editor", %{})
    view |> form("#image_form_form") |> render_submit(%{"image" => %{"credits" => %{"en" => "Edited"}}})

    assert_redirect(view, 3_000)
    assert Repo.get!(Brando.Images.Image, image.id).credits["en"] == "Edited"
  end
end
