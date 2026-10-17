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
