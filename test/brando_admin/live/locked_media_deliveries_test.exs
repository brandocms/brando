defmodule BrandoAdmin.LockedMediaDeliveriesTest do
  # A media input the user may not change (`LockedFields`: `readonly:` or
  # `disabled:`) takes no asset, however one reaches the form: a picker
  # selection, an upload delivery, a removal, a drawer's reset, a gallery
  # edit or a recovery copy. The same delivery to the open form (`:media`)
  # changes the field, so each case exercises the path it names.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias BrandoAdmin.Components.Form

  @form "#article_form_form"

  setup %{current_user: user} do
    stored = image(user)
    pdf = Repo.insert!(%Brando.Files.File{filename: "stored.pdf", filesize: 1, config_target: "default"})
    clip = Factory.insert(:video)
    gallery = Repo.insert!(%Brando.Galleries.Gallery{config_target: "default"})
    Repo.insert!(%Brando.Galleries.GalleryObject{gallery_id: gallery.id, image_id: stored.id, sequence: 0})

    {:ok, article} =
      SyncTest.create_article(%{title: "Media", slug: "media", language: "en", status: "published"}, user)

    article =
      article
      |> Ecto.Changeset.change(cover_id: stored.id, pdf_id: pdf.id, clip_id: clip.id, photos_id: gallery.id)
      |> Repo.update!()

    {:ok, article: article, stored: stored, pdf: pdf, clip: clip}
  end

  # The first submit asks the browser for the form (`b:submit`), the second saves
  defp save(view) do
    view |> form(@form) |> render_submit(%{"article" => %{"title" => "Saved"}})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form) |> render_submit(%{"article" => %{"title" => "Saved"}})
    assert_redirect(view, 3_000)
  end

  defp open(conn, article, form), do: live_form(conn, "/admin/articles/update/#{article.id}/#{form}", "article_form")

  # Handled before what the test sends next through the view
  defp send_form(view, message) do
    Phoenix.LiveView.send_update(view.pid, Form, [id: "article_form"] ++ message)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp gallery_images(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(#{@form} input[name^="article[photos][gallery_objects]"][name$="[image_id]"]))
    |> Floki.attribute("value")
  end

  defp saved(article), do: Repo.get!(Article, article.id)

  defp saved_gallery_images(article) do
    case saved(article).photos_id do
      nil ->
        []

      id ->
        Repo.all(
          from o in Brando.Galleries.GalleryObject, where: o.gallery_id == ^id, order_by: o.sequence, select: o.image_id
        )
    end
  end

  defp image(user),
    do: Factory.insert(:image, creator: user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)

  for {form, locked?} <- [media: false, locked_media: true] do
    describe "form #{form}" do
      @describetag form: form, locked: locked?

      test "a picker selection", %{conn: conn, article: article, stored: stored, current_user: user} = ctx do
        picked = image(user)
        {view, _html} = open(conn, article, ctx.form)

        # The field's drawer opens on it (`Input.Image` "open_image"), then the
        # picker selects another image
        send_form(view,
          action: :update_edit_image,
          edit_image: %{id: stored.id, path: [], field: :cover, relation_field: nil, image: stored}
        )

        send_form(view, action: :update_edit_image, image: picked)
        # Closing the drawer
        view |> with_target(cid_of(view, "#article_form-el")) |> render_hook("save_image", %{})

        expected = if ctx.locked, do: stored.id, else: picked.id
        save(view)
        assert saved(article).cover_id == expected
      end

      test "upload deliveries", %{conn: conn, article: article, stored: stored, pdf: pdf, clip: clip} = ctx do
        uploaded = image(ctx.current_user)
        new_pdf = Repo.insert!(%Brando.Files.File{filename: "new.pdf", filesize: 1, config_target: "default"})
        new_clip = Factory.insert(:video, remote_id: "new")
        {view, _html} = open(conn, article, ctx.form)

        for {type, {field, asset}} <- [image: {:cover, uploaded}, file: {:pdf, new_pdf}, video: {:clip, new_clip}] do
          send_form(view, event: "entry_field_upload_complete", asset_type: type, field: field, path: [], asset: asset)
        end

        send_form(view,
          event: "entry_field_upload_complete",
          asset_type: :gallery,
          field: :photos,
          path: [],
          asset: uploaded
        )

        expected =
          if ctx.locked,
            do: {stored.id, pdf.id, clip.id, [stored.id]},
            else: {uploaded.id, new_pdf.id, new_clip.id, [stored.id, uploaded.id]}

        {cover, file, video, images} = expected
        assert gallery_images(view) == Enum.map(images, &to_string/1)

        save(view)
        assert {saved(article).cover_id, saved(article).pdf_id, saved(article).clip_id} == {cover, file, video}
        assert saved_gallery_images(article) == images
      end

      test "a field's remove button", %{conn: conn, article: article, stored: stored, pdf: pdf, clip: clip} = ctx do
        {view, _html} = open(conn, article, ctx.form)

        for field <- [:cover, :pdf, :clip] do
          send_form(view, event: "clear_entry_field_asset", field: field, path: [])
        end

        expected = if ctx.locked, do: {stored.id, pdf.id, clip.id}, else: {nil, nil, nil}
        save(view)
        assert {saved(article).cover_id, saved(article).pdf_id, saved(article).clip_id} == expected
      end

      test "a drawer's reset", %{conn: conn, article: article, stored: stored, pdf: pdf, clip: clip} = ctx do
        {view, _html} = open(conn, article, ctx.form)
        form_cid = cid_of(view, "#article_form-el")

        for {action, key, asset, field, event} <- [
              {:update_edit_image, :edit_image, stored, :cover, "reset_image_field"},
              {:update_edit_file, :edit_file, pdf, :pdf, "reset_file_field"},
              {:update_edit_video, :edit_video, clip, :clip, "reset_video_field"}
            ] do
          asset_key = key |> to_string() |> String.replace_prefix("edit_", "") |> String.to_atom()
          edit = Map.put(%{id: asset.id, path: [], field: field, relation_field: nil}, asset_key, asset)
          send_form(view, [{:action, action}, {key, edit}])
          view |> with_target(form_cid) |> render_hook(event, %{})
        end

        expected = if ctx.locked, do: {stored.id, pdf.id, clip.id}, else: {nil, nil, nil}
        save(view)
        assert {saved(article).cover_id, saved(article).pdf_id, saved(article).clip_id} == expected
      end

      test "a gallery edit", %{conn: conn, article: article, stored: stored} = ctx do
        {view, _html} = open(conn, article, ctx.form)

        # What the gallery input sends when its last object is removed
        send_form(view, action: :put_gallery, path: [], key: :photos, gallery: %{config_target: "default", gallery_objects: []})

        expected = if ctx.locked, do: [stored.id], else: []
        save(view)
        assert saved_gallery_images(article) == expected
      end

      test "a recovery copy", %{conn: conn, article: article, stored: stored, current_user: user} = ctx do
        other = image(user)
        {view, _html} = open(conn, article, ctx.form)
        form_cid = cid_of(view, "#article_form-el")

        main =
          view
          |> render()
          |> form_params(@form)
          |> put_in(["article", "cover_id"], to_string(other.id))
          |> put_in(["article", "title"], "Restored")
          |> Plug.Conn.Query.encode()

        view
        |> with_target(form_cid)
        |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

        copy =
          Repo.one!(
            from d in Brando.Drafts.EntryDraft,
              where: d.entry_id == ^article.id and is_nil(d.resolved_at),
              order_by: [desc: d.id],
              limit: 1
          )

        view |> with_target(form_cid) |> render_hook("draft_restore", %{"id" => copy.id})
        view |> form(@form) |> render_submit(%{})
        assert_push_event(view, "b:submit", %{}, 2_000)
        view |> form(@form) |> render_submit(%{})
        assert_redirect(view, 3_000)

        expected = if ctx.locked, do: stored.id, else: other.id
        assert {saved(article).title, saved(article).cover_id} == {"Restored", expected}
      end
    end
  end
end
