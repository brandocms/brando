defmodule BrandoAdmin.SubformRelationTest do
  # An image field inside a subform row: picking, processing and removing it
  # keep the form alive and save onto the row.
  use Brando.LiveCase

  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem

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
    # The row's image is not the article's own `cover`.
    assert form_assigns(view).entry.cover == nil

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).cover_id == ctx.image.id
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
    # row's path, as the upload target carried it.
    send(view.pid, {ctx.image, [:image, :updated], [:items, 0]})

    assert row_cover_id(render(view)) == to_string(ctx.image.id)

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
