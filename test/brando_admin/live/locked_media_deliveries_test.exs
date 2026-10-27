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

  defp messages, do: self() |> Process.info(:messages) |> elem(1)

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "article_form")).assigns
  end

  defp saved_gallery_videos(article) do
    Repo.all(
      from o in Brando.Galleries.GalleryObject,
        where: o.gallery_id == ^saved(article).photos_id and not is_nil(o.video_id),
        select: o.video_id
    )
  end

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
        send_form(view,
          action: :put_gallery,
          path: [],
          key: :photos,
          gallery: %{config_target: "default", gallery_objects: []}
        )

        expected = if ctx.locked, do: [stored.id], else: []
        save(view)
        assert saved_gallery_images(article) == expected
      end

      test "a gallery video delivery", %{conn: conn, article: article} = ctx do
        video = Factory.insert(:video, remote_id: "gallery")
        {view, _html} = open(conn, article, ctx.form)

        send_form(view,
          event: "entry_field_upload_complete",
          asset_type: :gallery_video,
          field: :photos,
          path: [],
          asset: video
        )

        save(view)
        assert saved_gallery_videos(article) == if(ctx.locked, do: [], else: [video.id])
      end

      # The image editor's "save as new copy" for the field's image
      test "the image editor's new copy", %{conn: conn, article: article, stored: stored} = ctx do
        {view, _html} = open(conn, article, ctx.form)
        form_cid = cid_of(view, "#article_form-el")

        send_form(view,
          action: :update_edit_image,
          edit_image: %{id: stored.id, path: [], field: :cover, relation_field: nil, image: stored}
        )

        view
        |> with_target(form_cid)
        |> render_hook("image_editor_save", %{"mode" => "new_copy", "focal_x" => 40, "focal_y" => 60})

        images = Repo.aggregate(Brando.Images.Image, :count)
        Phoenix.PubSub.subscribe(Brando.pubsub(), "user:#{ctx.current_user.id}")
        jpeg = File.read!(Path.expand("../../fixtures/sample.jpg", __DIR__))

        view
        |> file_input("#article_form_form", :image_editor_upload, [%{name: "copy.jpg", content: jpeg, type: "image/jpeg"}])
        |> render_upload("copy.jpg")

        # Stored only for a field that takes it; the editor is told
        assert Repo.aggregate(Brando.Images.Image, :count) == if(ctx.locked, do: images, else: images + 1)

        if ctx.locked do
          assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "This field is locked"}}, 2_000
        else
          refute_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "This field is locked"}}, 300
        end
      end

      # The preview's copy of the field's asset (`Input.Image` on a pick, a
      # processed image's refresh)
      test "the field's relation in the preview", %{conn: conn, article: article, stored: stored} = ctx do
        other = image(ctx.current_user)
        {view, _html} = open(conn, article, ctx.form)

        send_form(view, event: "update_entry_relation", path: [:cover], updated_relation: other, update_entry: true)
        assert form_assigns(view).entry.cover.id == if(ctx.locked, do: stored.id, else: other.id)

        # The image a locked field holds, refreshed, is taken
        if ctx.locked do
          refreshed = %{stored | alt: %{"en" => "Refreshed"}}
          send_form(view, event: "update_entry_relation", path: [:cover], updated_relation: refreshed, update_entry: true)
          assert form_assigns(view).entry.cover.alt == %{"en" => "Refreshed"}
        end
      end

      # A drawer's provider upload (Mux, Bunny, Cloudflare, Vimeo)
      test "a provider upload in the video drawer", %{conn: conn, article: article, clip: clip} = ctx do
        {view, _html} = open(conn, article, ctx.form)

        send_form(view,
          action: :update_edit_video,
          edit_video: %{id: clip.id, path: [], field: :clip, relation_field: nil, video: clip}
        )

        if ctx.locked do
          videos = Repo.aggregate(Brando.Videos.Video, :count)

          send_form(view,
            action: :get_video_upload_url,
            upload_request: %{
              "request_ref" => "ref-1",
              "filename" => "clip.mp4",
              "size" => 1_000,
              "mime_type" => "video/mp4"
            }
          )

          assert_push_event(view, "video_upload_url_error", %{request_ref: "ref-1"})
          assert Repo.aggregate(Brando.Videos.Video, :count) == videos
        end

        # One started before, say: the provider is told the file is up either way
        uploading =
          Factory.insert(:video, type: :cloudflare, status: :uploading, remote_id: "cf-uid", creator: ctx.current_user)

        token = BrandoAdmin.Components.Assets.ProviderVideoUpload.upload_token(uploading, ctx.current_user, "ref-2")
        send_form(view, action: :video_upload_complete, upload: %{"upload_token" => token, "request_ref" => "ref-2"})
        assert Repo.get!(Brando.Videos.Video, uploading.id).status == :processing

        assert Ecto.Changeset.get_field(form_assigns(view).form.source, :clip_id) ==
                 if(ctx.locked, do: clip.id, else: uploading.id)
      end

      test "a subform's media input", %{conn: conn, article: article, current_user: user} = ctx do
        author = Repo.insert!(%Brando.SyncTest.ArticleAuthor{article_id: article.id, name: "Author"})
        portrait = image(user)
        {view, _html} = open(conn, article, ctx.form)

        send_form(view,
          event: "entry_field_upload_complete",
          asset_type: :image,
          field: :portrait,
          path: [:author],
          asset: portrait
        )

        save(view)
        assert Repo.get!(Brando.SyncTest.ArticleAuthor, author.id).portrait_id == portrait.id
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

        Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", Article, article.id))
        view |> with_target(form_cid) |> render_hook("draft_restore", %{"id" => copy.id})

        # Leaving a field ships what the editor changed to the other editors,
        # who could save it: a locked field is not among it
        view |> with_target(form_cid) |> render_hook("blur", %{"field" => "article[title]"})
        shipped = for {:fields_shipped, %{changes: changes}} <- messages(), change <- changes, do: change.field
        assert :title in shipped
        assert :cover_id in shipped == not ctx.locked

        view |> form(@form) |> render_submit(%{})
        assert_push_event(view, "b:submit", %{}, 2_000)
        view |> form(@form) |> render_submit(%{})
        assert_redirect(view, 3_000)

        expected = if ctx.locked, do: stored.id, else: other.id
        assert {saved(article).title, saved(article).cover_id} == {"Restored", expected}
      end
    end
  end

  # The lock is the field's "Save as new copy" was pressed in, though an
  # image editor opened since (a block's here) replaced `edit_image`
  test "the image editor's new copy keeps the field it was made in",
       %{conn: conn, article: article, stored: stored, current_user: user} do
    other = image(user)
    {view, _html} = open(conn, article, :locked_media)
    form_cid = cid_of(view, "#article_form-el")

    send_form(view,
      action: :update_edit_image,
      edit_image: %{id: stored.id, path: [], field: :cover, relation_field: nil, image: stored}
    )

    view
    |> with_target(form_cid)
    |> render_hook("image_editor_save", %{"mode" => "new_copy", "focal_x" => 40, "focal_y" => 60})

    send_form(view,
      action: :update_edit_image,
      edit_image: %{id: other.id, path: [], field: :cover, relation_field: nil, block_target: "block", image: other}
    )

    images = Repo.aggregate(Brando.Images.Image, :count)
    jpeg = File.read!(Path.expand("../../fixtures/sample.jpg", __DIR__))

    view
    |> file_input("#article_form_form", :image_editor_upload, [%{name: "copy.jpg", content: jpeg, type: "image/jpeg"}])
    |> render_upload("copy.jpg")

    assert Repo.aggregate(Brando.Images.Image, :count) == images
  end

  # `:unless_superuser`: a superuser's delivery is taken, anyone else's not
  for role <- [:superuser, :editor] do
    test "a field locked unless superuser, for a #{role}", %{article: article, stored: stored} do
      user = Factory.insert(:random_user, role: unquote(role), config: %Brando.Users.UserConfig{})
      conn = log_in_user(Phoenix.ConnTest.build_conn(), user)
      uploaded = image(user)
      {view, _html} = open(conn, article, :superuser_media)

      send_form(view, event: "entry_field_upload_complete", asset_type: :image, field: :cover, path: [], asset: uploaded)

      send_form(view,
        event: "entry_field_upload_complete",
        asset_type: :gallery,
        field: :photos,
        path: [],
        asset: uploaded
      )

      save(view)

      if unquote(role) == :superuser do
        assert saved(article).cover_id == uploaded.id
        assert saved_gallery_images(article) == [stored.id, uploaded.id]
      else
        assert saved(article).cover_id == stored.id
        assert saved_gallery_images(article) == [stored.id]
      end
    end
  end

  # Values the server builds into the form are kept for a locked gallery: a
  # synchronized translation's pending version, a revision's working copy
  for form <- [:media, :locked_media] do
    test "a translation's gallery, on form #{form}", %{conn: conn, current_user: user} do
      [first, second] = [image(user), image(user)]

      {:ok, source} =
        SyncTest.create_article(%{title: "Kilde", slug: "kilde", language: "no", status: "published"}, user)

      {:ok, target} = Brando.Translations.create_target(Article, source.id, :en, user)

      params = %{
        "photos" => %{
          "config_target" => "default",
          "gallery_objects" => [%{"image_id" => first.id, "sequence" => 0}, %{"image_id" => second.id, "sequence" => 1}]
        }
      }

      {:ok, _} =
        source
        |> Repo.preload(photos: :gallery_objects)
        |> Article.changeset(params, user)
        |> SyncTest.update_article(user)

      {view, _html} = open(conn, target, unquote(form))
      shown = Enum.map([first, second], &to_string(&1.id))
      await(fn -> gallery_images(view) == shown end)

      # A keystroke elsewhere casts the form again: the gallery stays the
      # translation's. (Saving a translation's gallery is not covered: the
      # save doesn't complete in this setup, locked or not.)
      view
      |> form(@form)
      |> render_change(%{"_target" => ["article", "title"], "article" => %{"title" => "Typed"}})

      assert gallery_images(view) == shown
    end

    test "a working copy's gallery, on form #{form}", %{conn: conn, article: article, current_user: user} do
      other = image(user)
      {view, _html} = open(conn, article, unquote(form))
      entry = form_assigns(view).entry

      gallery = %{
        entry.photos
        | gallery_objects: [%Brando.Galleries.GalleryObject{image_id: other.id, image: other, sequence: 0}]
      }

      send_form(view, action: :load_working_copy, revision: 1, revision_entry: %{entry | photos: gallery})
      save(view)

      assert saved_gallery_images(article) == [other.id]
    end

    # The working copy's assets are the server's while it is loaded. A
    # recovery copy restored after it is the browser's: a locked field
    # doesn't take it.
    test "a recovery copy after a working copy, on form #{form}", %{conn: conn, article: article} = ctx do
      [revised, forged] = [image(ctx.current_user), image(ctx.current_user)]
      {view, _html} = open(conn, article, unquote(form))
      form_cid = cid_of(view, "#article_form-el")
      entry = form_assigns(view).entry

      # An older copy, or a forged one
      main =
        view
        |> render()
        |> form_params(@form)
        |> put_in(["article", "cover_id"], to_string(forged.id))
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

      send_form(view,
        action: :load_working_copy,
        revision: 1,
        revision_entry: %{entry | cover_id: revised.id, cover: revised}
      )

      view |> with_target(form_cid) |> render_hook("draft_restore", %{"id" => copy.id})
      save(view)

      assert saved(article).cover_id == if(unquote(form) == :locked_media, do: ctx.stored.id, else: forged.id)
    end

    # A recovery copy taken while the working copy was loaded is a working
    # copy again: a locked field has the revision's assets, whatever the copy
    # holds for them
    test "a working copy's recovery copy, on form #{form}", %{conn: conn, article: article} = ctx do
      [revised, forged, other] = [image(ctx.current_user), image(ctx.current_user), image(ctx.current_user)]
      {view, _html} = open(conn, article, unquote(form))
      form_cid = cid_of(view, "#article_form-el")
      revision_entry = revised_entry(form_assigns(view).entry, revised, other, ctx.current_user)

      send_form(view, action: :load_working_copy, revision: revision_entry.revision, revision_entry: revision_entry.entry)

      main =
        view
        |> render()
        |> form_params(@form)
        |> put_in(["article", "cover_id"], to_string(forged.id))
        |> Plug.Conn.Query.encode()

      view
      |> with_target(form_cid)
      |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

      view |> with_target(form_cid) |> render_hook("draft_restore", %{"id" => latest_copy(article).id})
      save(view)

      assert saved(article).cover_id == if(unquote(form) == :locked_media, do: revised.id, else: forged.id)
      assert saved_gallery_images(article) == [other.id]
    end
  end

  # A working copy goes over to the editor's other tab as a working copy, its
  # locked assets with it
  for form <- [:media, :locked_media] do
    test "a working copy handed over to another tab, on form #{form}", %{conn: conn, article: article} = ctx do
      [revised, other] = [image(ctx.current_user), image(ctx.current_user)]
      a = open_tab(conn, article, unquote(form), "tab-a")
      revision_entry = revised_entry(form_assigns(a).entry, revised, other, ctx.current_user)
      send_form(a, action: :load_working_copy, revision: revision_entry.revision, revision_entry: revision_entry.entry)

      b = open_tab(conn, article, unquote(form), "tab-b")
      b |> element(~s([data-testid="tab-notice"] button[phx-click="brando_tab_claim"])) |> render_click()
      assert_push_event(a, "b:draft-release", %{})
      capture(a)
      await(fn -> form_assigns(b).working_copy == revision_entry.revision end)

      save(b)
      assert {saved(article).cover_id, saved_gallery_images(article)} == {revised.id, [other.id]}
    end

    # The copy of a tab that had no working copy: the form takes what doesn't
    # sync from it (a value typed that didn't cast here), and keeps its own
    # working copy's locked assets
    test "a handover to a tab with a working copy, on form #{form}", %{conn: conn, article: article} = ctx do
      [revised, other] = [image(ctx.current_user), image(ctx.current_user)]
      {view, _html} = open(conn, article, unquote(form))
      revision_entry = revised_entry(form_assigns(view).entry, revised, other, ctx.current_user)

      main = view |> render() |> form_params(@form) |> put_in(["article", "title"], "") |> Plug.Conn.Query.encode()
      capture(view, main)
      copy = latest_copy(article)

      send_form(view, action: :load_working_copy, revision: revision_entry.revision, revision_entry: revision_entry.entry)

      send_form(view,
        event: "tab_access",
        access: form_assigns(view).tab_access,
        handover: %{draft_id: copy.id, fields: ["title"]}
      )

      assert Keyword.has_key?(form_assigns(view).form.source.errors, :title)

      save(view)
      assert {saved(article).cover_id, saved_gallery_images(article)} == {revised.id, [other.id]}
    end
  end

  defp open_tab(conn, article, form, tab) do
    params = %{"brando_tab" => tab, "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _html} = conn |> Phoenix.LiveViewTest.put_connect_params(params) |> open(article, form)
    view
  end

  defp capture(view, main \\ nil) do
    main = main || view |> render() |> form_params(@form) |> Plug.Conn.Query.encode()

    view
    |> with_target(cid_of(view, "#article_form-el"))
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})
  end

  # A stored revision of `entry` with `cover` and a gallery of `image`
  defp revised_entry(entry, cover, image, user) do
    gallery = %{
      entry.photos
      | gallery_objects: [%Brando.Galleries.GalleryObject{image_id: image.id, image: image, sequence: 0}]
    }

    {:ok, revision} =
      Brando.Revisions.create_revision(%{entry | cover_id: cover.id, cover: cover, photos: gallery}, user, false)

    {:ok, {_revision, {number, revision_entry}}} = Brando.Revisions.get_revision(Article, entry.id, revision.revision)
    %{revision: number, entry: revision_entry}
  end

  defp latest_copy(article) do
    Repo.one!(
      from d in Brando.Drafts.EntryDraft,
        where: d.entry_id == ^article.id and is_nil(d.resolved_at),
        order_by: [desc: d.id],
        limit: 1
    )
  end

  # Another editor's change to a field this one may not change (a superuser's,
  # for `:unless_superuser`) doesn't enter this form: its save keeps what the
  # form has, here a working copy's cover
  for form <- [:media, :locked_media] do
    test "another editor's change, on form #{form}", %{conn: conn, article: article} = ctx do
      [revised, picked] = [image(ctx.current_user), image(ctx.current_user)]
      {a, _html} = open(conn, article, unquote(form))
      entry = form_assigns(a).entry

      send_form(a,
        action: :load_working_copy,
        revision: 1,
        revision_entry: %{entry | cover_id: revised.id, cover: revised}
      )

      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {b, _html} = open(log_in_user(Phoenix.ConnTest.build_conn(), other), article, :media)
      send_form(b, event: "entry_field_upload_complete", asset_type: :image, field: :cover, path: [], asset: picked)

      if unquote(form) == :media do
        await(fn -> Ecto.Changeset.get_field(form_assigns(a).form.source, :cover_id) == picked.id end)
      else
        Process.sleep(300)
        assert Ecto.Changeset.get_field(form_assigns(a).form.source, :cover_id) == revised.id
      end

      save(a)
      assert saved(article).cover_id == if(unquote(form) == :media, do: picked.id, else: revised.id)
    end
  end

  defp await(fun, tries \\ 40) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("timed out")
      true -> Process.sleep(50) && await(fun, tries - 1)
    end
  end
end
