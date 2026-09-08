defmodule BrandoAdmin.Components.ChangeTrackingRenderTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Phoenix.LiveViewTest

  alias BrandoAdmin.Components.Assets.FileBrowser

  defmodule PresenceHost do
    use Phoenix.LiveView, layout: false

    def mount(_, _, socket) do
      {:ok, socket |> Phoenix.Component.assign(:socket_connected, true) |> presences("online")}
    end

    def render(assigns), do: BrandoAdmin.Chrome.render(assigns)
    def handle_info(status, socket), do: {:noreply, presences(socket, status)}

    defp presences(socket, status) do
      presence = %{id: 42, name: "Fixture user", status: status, avatar: nil, urls: [], last_active: nil, last_seen: nil}
      {active, inactive} = if status == "online", do: {[presence], []}, else: {[], [presence]}

      socket
      |> Phoenix.Component.assign(:active_presences, active)
      |> Phoenix.Component.assign(:inactive_presences, inactive)
      |> stream(:active_presences, active, reset: true)
      |> stream(:inactive_presences, inactive, reset: true)
    end
  end

  defmodule GalleryHost do
    use Phoenix.LiveView, layout: false
    alias BrandoAdmin.Components.Form.Input.Gallery

    def mount(_, %{"image" => image}, socket) do
      gallery = %Brando.Galleries.Gallery{
        id: 1,
        gallery_objects: [%Brando.Galleries.GalleryObject{id: 1, image_id: image.id, image: image, config: %{}}]
      }

      changeset = Ecto.Changeset.change(%Brando.MigrationTest.ProjectUpdate1{photos: gallery})

      {:ok,
       socket
       |> Phoenix.Component.assign(:first, to_form(changeset, as: "first"))
       |> Phoenix.Component.assign(:second, to_form(changeset, as: "second"))}
    end

    def render(assigns) do
      ~H"""
      <div>
        <.live_component module={Gallery} id="first-gallery" field={@first[:photos]} opts={[layout: :list]} />
        <.live_component module={Gallery} id="second-gallery" field={@second[:photos]} opts={[layout: :list]} />
      </div>
      """
    end
  end

  test "presence moves between modal groups and avatar streams without leaving a stale row", %{conn: conn} do
    {:ok, view, _} = live_isolated(conn, PresenceHost)
    assert has_element?(view, "#presence-modal-online #presence-modal-user-42")
    assert has_element?(view, "#presences-active [data-user-id='42']")
    send(view.pid, "offline")
    render(view)
    refute has_element?(view, "#presence-modal-online #presence-modal-user-42")
    assert has_element?(view, "#presence-modal-offline #presence-modal-user-42")
    refute has_element?(view, "#presences-active [data-user-id='42']")
    assert has_element?(view, "#presences-inactive [data-user-id='42']")
    send(view.pid, "online")
    render(view)
    refute has_element?(view, "#presence-modal-offline #presence-modal-user-42")
    assert has_element?(view, "#presence-modal-online #presence-modal-user-42")
  end

  test "two gallery fields can configure the same row index with distinct component and input IDs", %{conn: conn} do
    image = Brando.Factory.insert(:image, creator: Brando.Factory.insert(:random_user))
    {:ok, view, _} = live_isolated(conn, GalleryHost, session: %{"image" => image})
    assert has_element?(view, "#first-gallery-object-config-modal")
    assert has_element?(view, "#second-gallery-object-config-modal")

    view |> element("#first_photos-sortable-gallery-objects button", "Configure") |> render_click()
    view |> element("#second_photos-sortable-gallery-objects button", "Configure") |> render_click()

    assert has_element?(view, "#first-gallery-object-config-modal #first-gallery-image-config-0_title")
    assert has_element?(view, "#second-gallery-object-config-modal #second-gallery-image-config-0_title")
    ids = view |> render() |> Floki.parse_document!() |> Floki.attribute("[id]", "id")
    assert Enum.uniq(ids) == ids

    view |> element("#first-gallery-object-config-modal button", "Cancel") |> render_click()
    refute has_element?(view, "#first-gallery-image-config-0_title")
    assert has_element?(view, "#second-gallery-image-config-0_title")
  end

  test "file browser wrappers retain child change tracking on unrelated updates" do
    for section <- [:top, :browser] do
      {:ok, socket} = FileBrowser.update(%{id: "browser", section: section}, %Phoenix.LiveView.Socket{})
      assigns = %{socket.assigns | __changed__: %{unrelated: true}}
      children = FileBrowser.render(assigns).dynamic.(true) |> Enum.filter(&match?(%Phoenix.LiveView.Rendered{}, &1))
      assert children != []
      for child <- children, do: assert(Enum.all?(child.dynamic.(true), &is_nil/1))
    end
  end
end
