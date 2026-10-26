defmodule BrandoAdmin.Components.Form.Input.GalleryVarAuthorizationTest do
  # A gallery var saves its gallery as it is edited, from a LiveComponent the
  # view's event check never sees. With group authorization that takes a
  # gallery grant, and only the gallery the var stores (or a new one) is
  # written: `gallery_id` round-trips through the form.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Users
  import Ecto.Query
  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Authorization.{Boundary, Scope}
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Galleries.{Gallery, GalleryObject}
  alias Brando.Repo
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias Phoenix.Component

  @preloads [gallery_objects: [:image, video: [:thumbnail, :file]]]

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    on_exit(fn -> Boundary.put_scope(nil) end)

    [first, second, third] = for _ <- 1..3, do: Factory.insert(:image)
    gallery = gallery([first, second])
    var = Repo.insert!(%Var{type: :gallery, key: "photos", label: "Photos", gallery_id: gallery.id})

    %{gallery: gallery, var: var, first: first, third: third}
  end

  defp gallery(images) do
    objects =
      images |> Enum.with_index() |> Enum.map(fn {image, i} -> %GalleryObject{image_id: image.id, sequence: i} end)

    %Gallery{config_target: "default", gallery_objects: objects} |> Repo.insert!() |> Repo.preload(@preloads)
  end

  defp image_ids(%{id: id}) do
    Repo.all(from(o in GalleryObject, where: o.gallery_id == ^id, order_by: o.sequence, select: o.image_id))
  end

  # As the view the var renders in: its scope is the logged-in user's
  defp socket_as(user, var, gallery) do
    Boundary.put_scope(Scope.current(user))

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:var, to_form(Ecto.Changeset.change(var)))
      |> Component.assign(:type, :gallery)
      |> Component.assign(:key, var.key)
      |> Component.assign(:gallery, gallery)
      |> Component.assign(:gallery_id, gallery && gallery.id)
      |> Component.assign(:current_user_id, user.id)
      |> Component.assign(:on_change, fn _ -> :ok end)

    %{socket | assigns: Map.put(socket.assigns, :myself, %Phoenix.LiveComponent.CID{cid: 1})}
  end

  defp user(grants), do: insert_user(permissions: ["brando.admin.access", "brando.pages.update" | grants])

  test "without a gallery grant the gallery stays as it was", c do
    socket = socket_as(user(~w(brando.galleries.read)), c.var, c.gallery)
    before = image_ids(c.gallery)

    RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)
    RenderVar.handle_event("remove_gallery_object", %{"id" => to_string(hd(c.gallery.gallery_objects).id)}, socket)

    assert image_ids(c.gallery) == before
  end

  test "with the update grant the var's gallery changes", c do
    socket = socket_as(user(~w(brando.galleries.read brando.galleries.update)), c.var, c.gallery)

    {:noreply, socket} = RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)
    assert c.third.id in image_ids(c.gallery)

    first_object = Enum.find(socket.assigns.gallery.gallery_objects, &(&1.image_id == c.first.id))
    RenderVar.handle_event("remove_gallery_object", %{"id" => to_string(first_object.id)}, socket)
    refute c.first.id in image_ids(c.gallery)
  end

  test "another entry's gallery named by the form is not written, even with the grant", c do
    others = gallery([c.first])
    Repo.insert!(%Var{type: :gallery, key: "other", label: "Other", gallery_id: others.id})
    socket = socket_as(user(~w(brando.galleries.read brando.galleries.update)), c.var, others)

    RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)

    assert image_ids(others) == [c.first.id]
  end

  test "a moved block's var, a new row, keeps writing the gallery it mounted with", c do
    # Moved into a container, the var is a new row; the old one holds the
    # gallery until the entry is saved. The component is the same one.
    moved = %Var{type: :gallery, key: "photos", label: "Photos", gallery_id: c.gallery.id}
    socket = socket_as(user(~w(brando.galleries.read brando.galleries.update)), moved, c.gallery)
    socket = Component.assign(socket, :own_gallery_ids, MapSet.new([c.gallery.id]))

    RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)

    assert c.third.id in image_ids(c.gallery)
  end

  test "in legacy mode an editor edits the var's gallery", c do
    put_test_env(:authorization_mode, :legacy)
    Boundary.put_scope(nil)
    editor = insert_user(role: :editor)
    socket = socket_as(editor, c.var, c.gallery)
    Boundary.put_scope(nil)

    RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)

    assert c.third.id in image_ids(c.gallery)
  end

  test "a new gallery takes the create grant", c do
    var = Repo.insert!(%Var{type: :gallery, key: "empty", label: "Empty"})
    count = Repo.aggregate(Gallery, :count)

    socket = socket_as(user(~w(brando.galleries.read)), var, nil)
    RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)
    assert Repo.aggregate(Gallery, :count) == count

    socket = socket_as(user(~w(brando.galleries.read brando.galleries.create)), var, nil)
    {:noreply, socket} = RenderVar.handle_event("select_image", %{"id" => to_string(c.third.id)}, socket)
    assert image_ids(socket.assigns.gallery) == [c.third.id]
  end
end
