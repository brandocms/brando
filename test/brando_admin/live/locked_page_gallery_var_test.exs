defmodule BrandoAdmin.LockedPageGalleryVarTest do
  # A page's own variables follow the source like a block's: a synchronized
  # translation's gallery variable holds the source's gallery, and writes it
  # as it is edited. The translation's form refuses those writes; the
  # source's form still makes them. (`LockedGalleryVarTest` covers block
  # variables.) Not async: `put_test_env(Page, …)` sets the application's
  # Page configuration, which tests beside it would see.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Var
  alias Brando.Galleries.{Gallery, GalleryObject}
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Translations
  alias BrandoAdmin.Components.Form.Input.RenderVar

  setup %{current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)

    gallery =
      Repo.insert!(%Gallery{
        config_target: "default",
        gallery_objects: [
          %GalleryObject{image_id: first.id, sequence: 0},
          %GalleryObject{image_id: second.id, sequence: 1}
        ]
      })

    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)

    Repo.insert!(%Var{
      type: :gallery,
      key: "album",
      label: %{"en" => "Album"},
      page_id: source.id,
      gallery_id: gallery.id
    })

    {:ok, target} = Translations.create_target(Page, source.id, :en, user)
    # The source's next save points the translation's variable at the
    # source's gallery (its pending version)
    {:ok, _} = Brando.Pages.update_page(source.id, %{title: "Om oss, endret"}, user)

    %{source: source, target: target, gallery: gallery, third: third}
  end

  defp media(%{id: id}) do
    Repo.all(from(o in GalleryObject, where: o.gallery_id == ^id, order_by: o.sequence, select: o.image_id))
  end

  defp stored_gallery_id(%{id: id}),
    do: Repo.one(from(v in Var, where: v.page_id == ^id and v.key == "album", select: v.gallery_id))

  defp open(conn, id) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{id}")
    await_selector(view, "[data-block-uid], #page_form_form")
    view
  end

  defp var_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns
  end

  defp var_component(view), do: with_target(view, var_assigns(view).myself.cid)

  defp save(view) do
    view |> form("#page_form_form") |> render_submit(%{})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#page_form_form") |> render_submit(%{})
    assert_redirect(view, 3_000)
  end

  describe "in a synchronized translation" do
    # Saved with the source's changes, as an editor does: from then on its
    # variable stores the source's gallery
    setup %{conn: conn, target: target, current_user: user} do
      view = open(conn, target.id)
      await_selector(view, "input[name='translation_review[version_id]']")
      save(view)

      view = open(conn, target.id)
      Brando.endpoint().subscribe("user:#{user.id}")
      %{view: view}
    end

    test "the variable stores the source's gallery", c do
      assert stored_gallery_id(c.target) == c.gallery.id
      assert var_assigns(c.view).gallery_id == c.gallery.id
    end

    test "choosing an image, or removing one, leaves the source's gallery as it was", c do
      notice = Gettext.dgettext(Brando.Gettext, "default", "Media follows the source; choose it there.")
      before = media(c.gallery)
      [object | _] = Repo.preload(c.gallery, :gallery_objects, force: true).gallery_objects

      c.view |> var_component() |> render_click("select_image", %{"id" => to_string(c.third.id)})
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: ^notice}}, 2_000

      c.view |> var_component() |> render_click("remove_gallery_object", %{"id" => to_string(object.id)})
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: ^notice}}, 2_000

      assert media(c.gallery) == before
    end
  end

  describe "in the source" do
    test "choosing an image adds it to the gallery", c do
      view = open(c.conn, c.source.id)
      view |> var_component() |> render_click("select_image", %{"id" => to_string(c.third.id)})
      assert c.third.id in media(c.gallery)
    end
  end
end
