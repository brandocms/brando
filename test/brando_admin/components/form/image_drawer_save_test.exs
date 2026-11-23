defmodule BrandoAdmin.Components.Form.ImageDrawerSaveTest do
  # The image drawer's save (`save_image`) when the image's context refuses
  # the changes as invalid: the form says so and the drawer closes, as for a
  # refused save, since the browser has hidden it already.
  use Brando.LiveCase

  alias Brando.Images.Focal
  alias Brando.Images.Image
  alias Brando.SyncTest
  alias BrandoAdmin.Components.Form

  setup %{conn: conn, current_user: user} do
    image = Factory.insert(:image, creator: user, focal: %Focal{x: 50, y: 50}, status: :processed)

    {:ok, article} =
      SyncTest.create_article(%{title: "Media", slug: "media", language: "en", status: "published"}, user)

    article = article |> Ecto.Changeset.change(cover_id: image.id) |> Repo.update!()
    Phoenix.PubSub.subscribe(Brando.pubsub(), "user:#{user.id}")

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/media", "article_form")

    Phoenix.LiveView.send_update(view.pid, Form,
      id: "article_form",
      action: :update_edit_image,
      edit_image: %{id: image.id, path: [], field: :cover, relation_field: nil, schema: SyncTest.Article, image: image}
    )

    _ = :sys.get_state(view.pid)
    {:ok, view: view, image: image}
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "article_form")).assigns
  end

  test "an invalid focal point is not saved, and the form says so", %{view: view, image: image} do
    assert form_assigns(view).editing_image?

    view
    |> with_target(cid_of(view, "#article_form-el"))
    |> render_hook("save_image", %{"image" => %{"title" => %{"en" => "Changed"}, "focal" => %{"x" => "left"}}})

    assert Process.alive?(view.pid)
    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}, 2_000
    refute form_assigns(view).editing_image?

    stored = Repo.get!(Image, image.id)
    assert stored.title == image.title
    assert %{x: 50, y: 50} = stored.focal
  end
end
