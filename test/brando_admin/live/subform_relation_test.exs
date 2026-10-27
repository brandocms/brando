defmodule BrandoAdmin.SubformRelationTest do
  # An image field inside a subform row: picking, processing and removing it
  # keep the form alive and save onto the row.
  use Brando.LiveCase

  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleAuthor
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Image
  alias BrandoAdmin.Components.Form.Input.Video

  @form "#article_form_form"
  @sample Path.expand("../../fixtures/sample.jpg", __DIR__)
  @row_cover ~s(input[name="article[items][0][cover_id]"])
  @row_media "#article_items_0_cover-media"
  @row_clip ~s(input[name="article[items][0][clip_id]"])

  setup %{current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Article", slug: "article", language: "en", status: "published", items: [%{label: "Row"}]},
        user
      )

    image =
      Factory.insert(:image,
        creator: user,
        config_target: "image:Brando.SyncTest.ArticleItem:cover",
        focal: %Brando.Images.Focal{x: 50, y: 50},
        status: :processed
      )

    [item] = Repo.preload(article, :items).items
    %{article: article, item: item, image: image}
  end

  test "a picked image in a subform row is saved on the row", ctx do
    view = open(ctx)
    pick(view, ctx.image)
    assert row_cover_id(render(view)) == to_string(ctx.image.id)
    assert has_element?(view, "#{@row_media} img")
    # The row's image is not the article's own `cover`, in the entry or in
    # the input the browser is told to validate.
    assert form_assigns(view).entry.cover == nil
    image_id = ctx.image.id
    assert_push_event(view, "b:validate", %{target: "article[items][0][cover_id]", value: ^image_id})

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).cover_id == ctx.image.id
  end

  # Committing an image re-bakes the changeset (`commit_entry_field_asset`),
  # which drops a removed row that is still pending: the form, the preview,
  # the next `validate` and the save still treat it as removed.
  test "an image picked in a row while another row's removal is pending", ctx do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Example Hotel",
          slug: "example-hotel",
          language: "en",
          status: "published",
          items: [%{label: "A"}, %{label: "B"}, %{label: "C"}]
        },
        ctx.current_user
      )

    [a, b, c] = article |> Repo.preload(:items) |> Map.get(:items) |> Enum.sort_by(& &1.label)
    view = open(%{ctx | article: article})

    view
    |> with_target(cid_of(view, ~s(input[name="article[items][1][label]"])))
    |> render_click("remove_subentry", %{"key" => "id-#{b.id}"})

    assert row_labels(render(view)) == ["A", "C"]

    assert %Ecto.Changeset{action: :replace} =
             Enum.find(form_assigns(view).form.source.changes.items, &(&1.data.id == b.id))

    view
    |> with_target(cid_of(view, ~s(input[name="article[items][1][cover_id]"])))
    |> render_click("select_image", %{"id" => to_string(ctx.image.id)})

    # The form, and the entry the preview renders (the changeset with the
    # form's relations over it), before the browser's next `validate`
    html = render(view)
    assert row_labels(html) == ["A", "C"]

    assert html |> Floki.parse_document!() |> Floki.attribute(~s(input[name="article[items][1][cover_id]"]), "value") == [
             to_string(ctx.image.id)
           ]

    assigns = form_assigns(view)
    previewed = assigns.form.source |> Brando.Utils.apply_changes_recursively() |> Map.merge(assigns.updated_entry_assocs)
    assert Enum.map(previewed.items, & &1.label) == ["A", "C"]
    assert Enum.find(previewed.items, &(&1.id == c.id)).cover.id == ctx.image.id

    # The browser's `validate` after the pick (`b:validate`)
    params = view |> render() |> form_params(@form) |> Map.put("_target", ["article", "items", "1", "cover_id"])
    view |> element(@form) |> render_change(params)

    rows = form_assigns(view).form.source.changes.items
    assert %Ecto.Changeset{action: :replace} = Enum.find(rows, &(&1.data.id == b.id))
    assert row_labels(render(view)) == ["A", "C"]

    save(view)

    saved = ArticleItem |> Repo.all() |> Enum.filter(&(&1.article_id == article.id)) |> Enum.sort_by(& &1.label)
    assert Enum.map(saved, &{&1.id, &1.cover_id}) == [{a.id, nil}, {c.id, ctx.image.id}]
    refute Repo.get(ArticleItem, b.id)
  end

  defp row_labels(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(input[name^="article[items]"][name$="[label]"]))
    |> Floki.attribute("value")
  end

  test "a row's picked image replacing another stays shown through an edit", ctx do
    first = insert_image(ctx, "first", "First")
    ctx.item |> Ecto.Changeset.change(cover_id: first.id) |> Repo.update!()
    second = insert_image(ctx, "second", "Second")

    view = open(ctx)
    assert view |> element(@row_media) |> render() =~ "first.jpg"
    pick(view, second)
    assert view |> element(@row_media) |> render() =~ "second.jpg"

    edit_row_label(view)

    assert row_cover_id(render(view)) == to_string(second.id)
    assert view |> element(@row_media) |> render() =~ "second.jpg"

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).cover_id == second.id
  end

  test "a picked video in a subform row is saved on the row", ctx do
    video = Factory.insert(:video, creator: ctx.current_user)
    view = open(ctx)

    view
    |> with_target(cid_of(view, @row_clip))
    |> render_click("select_video", %{"id" => to_string(video.id)})

    assert view |> render() |> Floki.parse_document!() |> Floki.attribute(@row_clip, "value") == [to_string(video.id)]

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).clip_id == video.id
  end

  test "an image in a subform row that finishes processing keeps the form alive", ctx do
    view = open(ctx)
    pick(view, ctx.image)

    # What `ImageProcessor` broadcasts when an upload to the row is done: the
    # row's path and the field, as the upload manager queued it.
    send(view.pid, {ctx.image, [:image, :updated], [:items, 0, :cover]})

    assert row_cover_id(render(view)) == to_string(ctx.image.id)
    image_id = ctx.image.id
    assert [%{cover: %{id: ^image_id}}] = form_assigns(view).entry.items

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).cover_id == ctx.image.id
  end

  test "removing the image from a subform row keeps the form alive and saves", ctx do
    ctx.item |> Ecto.Changeset.change(cover_id: ctx.image.id) |> Repo.update!()
    view = open(ctx)
    assert row_cover_id(render(view)) == to_string(ctx.image.id)

    view
    |> with_target(cid_of(view, @row_cover))
    |> render_click("remove_image", %{})

    assert row_cover_id(render(view)) == ""
    refute has_element?(view, "#{@row_media} img")

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).cover_id == nil
  end

  test "a row's media field takes the form id the subform hands it", ctx do
    # A row whose schema has no relation named after the form (`project`), so
    # the id cannot be derived from the row's form name.
    item = Repo.preload(ctx.item, [:cover, :clip])
    row = Phoenix.Component.to_form(Ecto.Changeset.change(item), as: "project[items][0]")

    for {input, field, open} <- [{Image, :cover, "open_image"}, {Video, :clip, "open_video"}] do
      {:ok, socket} =
        input.mount(%Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, flash: %{}, myself: %Phoenix.LiveComponent.CID{cid: 1}}
        })

      {:ok, socket} =
        input.update(
          %{
            id: "row-#{field}",
            field: row[field],
            form_id: nil,
            parent_form_id: "project_form",
            path: [:items, 0],
            current_user: ctx.current_user,
            label: "Media",
            instructions: nil,
            placeholder: nil,
            opts: [],
            subform_id: nil,
            parent_form: nil
          },
          socket
        )

      assert socket.assigns.form_id == "project_form"

      # Opening the field's drawer.
      assert {:noreply, socket} = input.handle_event(open, %{}, socket)
      assert socket.assigns.form_id == "project_form"
      assert_received {:phoenix, :send_update, {{Form, "project_form"}, %{event: "focus_field"}}}
    end
  end

  test "a row's picked image is put on the same row after a row above is removed", ctx do
    second_item = insert_item(ctx, "Second")
    first = insert_image(ctx, "first", "First")
    second = insert_image(ctx, "second", "Second")
    third = insert_image(ctx, "third", "Third")
    ctx.item |> Ecto.Changeset.change(cover_id: first.id) |> Repo.update!()
    second_item |> Ecto.Changeset.change(cover_id: second.id) |> Repo.update!()

    view = open(ctx)

    view
    |> with_target(cid_of(view, ~s(input[name="article[items][0][label]"])))
    |> render_hook("remove_subentry", %{"key" => "id-#{ctx.item.id}"})

    settle(view)
    assert view |> element(@row_media) |> render() =~ "second.jpg"

    pick(view, third)
    edit_row_label(view)

    assert row_cover_id(render(view)) == to_string(third.id)
    assert view |> element(@row_media) |> render() =~ "third.jpg"

    save(view)
    assert Repo.get!(ArticleItem, second_item.id).cover_id == third.id
    refute Repo.get(ArticleItem, ctx.item.id)
  end

  test "a processed image lands on its row after a row marked for deletion", ctx do
    second_item = insert_item(ctx, "Second")
    second_cover = ~s(input[name="article[items][1][cover_id]"])
    view = open(ctx)

    view
    |> with_target(cid_of(view, second_cover))
    |> render_click("select_image", %{"id" => to_string(ctx.image.id)})

    # The first row marked for deletion is still a row of the form.
    params =
      view
      |> render()
      |> form_params(@form)
      |> put_in(["article", "items", "0", "marked_as_deleted"], "true")
      |> Map.put("_target", ["article", "items", "0", "marked_as_deleted"])

    view |> element(@form) |> render_change(params)
    assert [%{action: :delete}, _] = form_assigns(view).form.source.changes.items
    assert has_element?(view, second_cover)

    processed = %{ctx.image | path: "image/processed.jpg"}
    send(view.pid, {processed, [:image, :updated], [:items, 1, :cover]})
    render(view)

    second_id = second_item.id

    assert %{cover: %{path: "image/processed.jpg"}} =
             Enum.find(form_assigns(view).entry.items, &(&1.id == second_id))
  end

  # A row marked for deletion is still a row of the form until the
  # browser's next change (`PendingRows` then takes it out), so a delivery's
  # path counts it. The deliveries write through `put_key_at/4`: the picker,
  # the upload manager, a provider upload and the image editor's copy
  # (`commit_entry_field_asset`), and the drawers' saves.
  describe "a delivery to a row after a row marked for deletion" do
    setup ctx do
      {:ok, article} =
        SyncTest.create_article(
          %{
            title: "Example Hotel",
            slug: "example-hotel",
            language: "en",
            status: "published",
            items: [%{label: "A"}, %{label: "B"}, %{label: "C"}]
          },
          ctx.current_user
        )

      [a, b, c] = article |> Repo.preload(:items) |> Map.get(:items) |> Enum.sort_by(& &1.label)
      %{article: article, a: a, b: b, c: c}
    end

    test "a picked image goes on its row", ctx do
      view = open(ctx)
      mark_row(view, 0, "true")
      assert [%{action: :delete}, _, _] = form_rows(view)

      view
      |> with_target(cid_of(view, ~s(input[name="article[items][2][cover_id]"])))
      |> render_click("select_image", %{"id" => to_string(ctx.image.id)})

      assert_delivered(view, ctx, ["", "", to_string(ctx.image.id)])
      save(view)
      assert saved_covers(ctx) == [{ctx.b.id, nil}, {ctx.c.id, ctx.image.id}]
    end

    test "an uploaded image goes on its row", ctx do
      view = open(ctx)
      mark_row(view, 0, "true")

      deliver_upload(view, [:items, 2], ctx.image)
      assert_delivered(view, ctx, ["", "", to_string(ctx.image.id)])
      save(view)
      assert saved_covers(ctx) == [{ctx.b.id, nil}, {ctx.c.id, ctx.image.id}]
    end

    # The picker's "edit image" on the third row's field, then the drawer's
    # save
    test "an image saved in the row's drawer goes on its row", ctx do
      view = open(ctx)
      mark_row(view, 0, "true")

      send_form(view,
        action: :update_edit_image,
        edit_image: %{id: nil, path: [:items, 2], field: :cover, relation_field: nil, image: nil}
      )

      send_form(view, action: :open_image_editor_from_picker, image: ctx.image)
      view |> with_target(cid_of(view, "#article_form-el")) |> render_hook("save_image", %{"image" => %{}})

      assert_delivered(view, ctx, ["", "", to_string(ctx.image.id)])
      save(view)
      assert saved_covers(ctx) == [{ctx.b.id, nil}, {ctx.c.id, ctx.image.id}]
    end

    # The image editor's "save as new copy" in the third row's drawer
    test "the image editor's new copy goes on its row", ctx do
      ctx.c |> Ecto.Changeset.change(cover_id: ctx.image.id) |> Repo.update!()
      view = open(ctx)
      mark_row(view, 0, "true")

      send_form(view,
        action: :update_edit_image,
        edit_image: %{id: ctx.image.id, path: [:items, 2], field: :cover, relation_field: nil, image: ctx.image}
      )

      view
      |> with_target(cid_of(view, "#article_form-el"))
      |> render_hook("image_editor_save", %{"mode" => "new_copy", "focal_x" => 40, "focal_y" => 60})

      view
      |> file_input(@form, :image_editor_upload, [%{name: "copy.jpg", content: File.read!(@sample), type: "image/jpeg"}])
      |> render_upload("copy.jpg")

      copy = Brando.Images.Image |> Ecto.Query.last(:id) |> Repo.one!()
      assert copy.id != ctx.image.id

      assert [%{action: :delete}, b, c] = form_rows(view)
      assert {Ecto.Changeset.get_field(b, :cover_id), Ecto.Changeset.get_field(c, :cover_id)} == {nil, copy.id}
    end

    # The browser's next change after the mark, here taking it back: the row
    # being removed from the browser's list, `PendingRows` leaves it out
    # (the form has no input for the mark). A delivery then goes to the third
    # row wherever the form shows it.
    test "a row marked and then unmarked", ctx do
      view = open(ctx)
      mark_row(view, 0, "true")
      mark_row(view, 0, "false")

      index = view |> render() |> row_labels() |> Enum.find_index(&(&1 == "C"))
      deliver_upload(view, [:items, index], ctx.image)

      covers = view |> render() |> row_labels() |> Enum.zip(cover_ids(render(view)))
      assert {"B", ""} in covers
      assert {"C", to_string(ctx.image.id)} in covers

      save(view)
      covers = saved_covers(ctx)
      assert {ctx.b.id, nil} in covers
      assert {ctx.c.id, ctx.image.id} in covers
    end

    # The form right after the delivery, and after the browser's `validate`
    # that follows it (`b:validate`), which takes the marked row out of the
    # form.
    defp assert_delivered(view, ctx, covers) do
      image_id = ctx.image.id
      assert_push_event(view, "b:validate", %{target: "article[items][2][cover_id]", value: ^image_id})
      assert [%{action: :delete}, _, _] = form_rows(view)

      html = render(view)
      assert cover_ids(html) == covers

      params = html |> form_params(@form) |> Map.put("_target", ["article", "items", "2", "cover_id"])
      view |> element(@form) |> render_change(params)
      assert cover_ids(render(view)) == tl(covers)
    end

    defp mark_row(view, index, marked) do
      index = to_string(index)

      params =
        view
        |> render()
        |> form_params(@form)
        |> put_in(["article", "items", index, "marked_as_deleted"], marked)
        |> Map.put("_target", ["article", "items", index, "marked_as_deleted"])

      view |> element(@form) |> render_change(params)
    end

    # What the upload manager sends the form when an upload to a row's image
    # field is stored
    defp deliver_upload(view, path, image) do
      send_form(view, event: "entry_field_upload_complete", asset_type: :image, field: :cover, path: path, asset: image)
    end

    defp send_form(view, message) do
      Phoenix.LiveView.send_update(view.pid, Form, [id: "article_form"] ++ message)
      _ = :sys.get_state(view.pid)
    end

    defp form_rows(view), do: form_assigns(view).form.source.changes.items

    defp cover_ids(html) do
      html
      |> Floki.parse_document!()
      |> Floki.find(~s(#{@form} input[name^="article[items]"][name$="[cover_id]"]))
      |> Floki.attribute("value")
    end

    defp saved_covers(%{article: article}) do
      ArticleItem
      |> Repo.all()
      |> Enum.filter(&(&1.article_id == article.id))
      |> Enum.sort_by(& &1.label)
      |> Enum.map(&{&1.id, &1.cover_id})
    end
  end

  test "a processed image whose row path is stale leaves the rows alone", ctx do
    view = open(ctx)

    # Rows a processing job's path named before they were removed or moved.
    send(view.pid, {ctx.image, [:image, :updated], [:items, 3, :cover]})
    send(view.pid, {ctx.image, [:image, :updated], [:items, 0, :cover]})

    assert row_cover_id(render(view)) == ""
    assert [%{cover: nil}] = form_assigns(view).entry.items
  end

  describe "a one-to-one subform" do
    @author_portrait ~s(input[name="article[author][portrait_id]"])
    @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

    setup ctx do
      author = Repo.insert!(%ArticleAuthor{article_id: ctx.article.id, name: "Example Author"})

      image =
        Factory.insert(:image,
          creator: ctx.current_user,
          config_target: "image:Brando.SyncTest.ArticleAuthor:portrait",
          focal: %Brando.Images.Focal{x: 50, y: 50},
          status: :processed
        )

      %{author: author, portrait: image}
    end

    test "opens with its saved image on the form's automatic preloads", ctx do
      ctx.author |> Ecto.Changeset.change(portrait_id: ctx.portrait.id) |> Repo.update!()
      view = open_author(ctx)

      assert author_portrait_id(render(view)) == to_string(ctx.portrait.id)
      assert has_element?(view, ~s([id$="_portrait-media"] img))
      assert %ArticleAuthor{portrait: %{id: portrait_id}} = form_assigns(view).entry.author
      assert portrait_id == ctx.portrait.id
    end

    test "an upload to its image field is processed for that field", ctx do
      view = open_author(ctx)
      manager = find_live_child(view, "brando-upload-manager-lv")
      test_pid = self()
      handler = "subform-relation-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:oban, :job, :start],
        fn _event, _measurements, %{job: job}, _config ->
          if job.worker == "Brando.Worker.ImageProcessor", do: send(test_pid, {:image_job, job.args})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      ref = intake(manager, form_assigns(view).deliver_topic)
      name = "#{ref}::sample.jpg"
      upload = file_input(manager, "form#brando-upload-manager-queue-form", :queue, [file(name)])
      render_upload(upload, name)

      # The path the processed image comes back with names the field, not
      # only the subform it is in.
      assert_receive {:image_job, %{"field_full_path" => ["author", "portrait"]}}

      settle(view)
      %{asset_id: portrait_id} = :sys.get_state(manager.pid).socket.assigns.items[ref]
      assert %ArticleAuthor{portrait: %{id: ^portrait_id}} = form_assigns(view).entry.author
      assert author_portrait_id(render(view)) == to_string(portrait_id)

      save(view)
      assert Repo.get!(ArticleAuthor, ctx.author.id).portrait_id == portrait_id
    end

    test "an image that finishes processing lands on its field", ctx do
      ctx.author |> Ecto.Changeset.change(portrait_id: ctx.portrait.id) |> Repo.update!()
      view = open_author(ctx)

      send(view.pid, {ctx.portrait, [:image, :updated], [:author, :portrait]})

      assert %ArticleAuthor{portrait: %{id: portrait_id}} = form_assigns(view).entry.author
      assert portrait_id == ctx.portrait.id
      refute Map.has_key?(form_assigns(view).updated_entry_assocs, :author)
      assert author_portrait_id(render(view)) == to_string(ctx.portrait.id)

      save(view)
      assert Repo.get!(ArticleAuthor, ctx.author.id).portrait_id == ctx.portrait.id
    end

    defp open_author(%{conn: conn, article: article}) do
      {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/author", "article_form")
      view
    end

    defp intake(manager, deliver_topic) do
      render_hook(manager, "intake", %{
        "files" => [%{"index" => 0, "name" => "sample.jpg", "size" => 1_000, "type" => "image/jpeg"}],
        "target" => %{
          "kind" => "entry_field",
          "field" => "portrait",
          "path" => ["author"],
          "asset_type" => "image",
          "config_target" => "image:Brando.SyncTest.ArticleAuthor:portrait",
          "deliver_topic" => deliver_topic
        }
      })

      [ref] = :sys.get_state(manager.pid).socket.assigns.items |> Map.keys()
      ref
    end

    defp file(name), do: %{name: name, content: File.read!(@fixture), type: "image/jpeg"}

    defp author_portrait_id(html) do
      html
      |> Floki.parse_document!()
      |> Floki.find(@author_portrait)
      |> Floki.attribute("value")
      |> List.first()
    end
  end

  # The image drawer open on a row added since the last save: after a
  # reconnect the form's own rows come back from the recovered params.
  test "an open drawer on an unsaved row comes back after a reconnect", ctx do
    view = open(ctx)

    view
    |> with_target(cid_of(view, ~s(input[name="article[items][0][label]"])))
    |> render_click("add_subentry", %{})

    settle(view)
    new_cover = ~s(input[name="article[items][1][cover_id]"])
    assert has_element?(view, new_cover)

    view |> with_target(cid_of(view, new_cover)) |> render_click("open_image", %{})
    view |> with_target(cid_of(view, new_cover)) |> render_click("select_image", %{"id" => to_string(ctx.image.id)})
    captured = render(view)

    assert form_params(captured, "#article_form-drawer-recovery")["drawer"]["path"] == ~s(["items",1])

    kill_live(view)
    view = open(ctx)
    recover(view, captured)

    assert %{editing_image?: true, edit_image: %{path: [:items, 1], field: :cover}} = form_assigns(view)
  end

  # What LiveView does on a rejoin: each form the old page had that the new
  # one renders, in the new page's document order, sends its
  # `phx-auto-recover` event with the old page's values.
  defp recover(view, captured) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("form[phx-auto-recover]")
    |> Enum.each(fn form ->
      id = "#" <> hd(Floki.attribute(form, "id"))

      case Floki.attribute(form, "phx-auto-recover") do
        ["recover_form"] ->
          view |> element(id) |> render_change(recovery_params(captured, id))

        ["recover_drawer_state"] ->
          view |> with_target(cid_of(view, id)) |> render_hook("recover_drawer_state", form_params(captured, id))

        _ ->
          :ok
      end
    end)
  end

  defp edit_row_label(view) do
    params =
      view
      |> render()
      |> form_params(@form)
      |> put_in(["article", "items", "0", "label"], "Edited")
      |> Map.put("_target", ["article", "items", "0", "label"])

    view |> element(@form) |> render_change(params)
  end

  defp insert_item(ctx, label) do
    Repo.insert!(%ArticleItem{article_id: ctx.article.id, label: label, sequence: 1, uid: Brando.Utils.generate_uid()})
  end

  defp insert_image(ctx, name, title) do
    Factory.insert(:image,
      creator: ctx.current_user,
      config_target: "image:Brando.SyncTest.ArticleItem:cover",
      focal: %Brando.Images.Focal{x: 50, y: 50},
      status: :processed,
      path: "image/#{name}.jpg",
      title: %{"en" => title}
    )
  end

  defp open(%{conn: conn, article: article}) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")
    view
  end

  # The image picker selecting `image` for the row's image field (its
  # `event_target`).
  defp pick(view, image) do
    view
    |> with_target(cid_of(view, @row_cover))
    |> render_click("select_image", %{"id" => to_string(image.id)})
  end

  defp form_assigns(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns
      _ -> nil
    end)
  end

  defp row_cover_id(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(@row_cover)
    |> Floki.attribute("value")
    |> List.first()
  end

  # The first submit collects the block fields; the Submit hook then submits
  # again (`b:submit`), which saves and returns to the listing.
  defp save(view) do
    view |> form(@form) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form) |> render_submit()
    assert_redirect(view, 3_000)
  end
end
