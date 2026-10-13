defmodule BrandoAdmin.Components.Form.VideoThumbnailPickTest do
  # A thumbnail picked from the whole library is copied beside the page, and
  # the copy can be ready after the video drawer has moved on to another
  # video. The picker is not reopened for that one, so the pick has to name
  # its video; it goes to that video, never to the one now in the drawer.
  #
  # Driven through the handlers the browser reaches: the drawer's "Select
  # image" (`browse_video_thumbnail`), the picker opening it sends, the copy's
  # reply, and the `select_image` the picker's hook sends on with the reply.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.ImagePicker
  alias Ecto.Changeset
  alias Phoenix.Component

  @form_cid %Phoenix.LiveComponent.CID{cid: 3}

  setup do
    user = Factory.insert(:random_user)
    video_a = Factory.insert(:video, creator_id: user.id)
    video_b = Factory.insert(:video, creator_id: user.id)
    thumbnail = Factory.insert(:image, creator_id: user.id, config_target: "default", status: :processed)
    page = Factory.insert(:page, creator: user)
    {:ok, user: user, video_a: video_a, video_b: video_b, thumbnail: thumbnail, page: page}
  end

  defp form_socket(page, user, video) do
    socket = %Phoenix.LiveView.Socket{}
    socket = %{socket | assigns: Map.put(socket.assigns, :myself, @form_cid)}

    socket
    |> Component.assign(:id, "page_form")
    |> Component.assign(:form, to_form(Changeset.change(page)))
    |> Component.assign(:entry, page)
    |> Component.assign(:current_user, user)
    |> Component.assign(:edit_video, %{video: video, path: [], field: :video})
  end

  defp picker(user) do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }

    {:ok, socket} = ImagePicker.mount(socket)
    %{socket | assigns: Map.merge(socket.assigns, %{id: "image-picker", upload_in_form?: true, current_user: user})}
  end

  # The opening the form sent the picker, applied as LiveView would
  defp open_picker(picker) do
    assert_received {:phoenix, :send_update, {{ImagePicker, "image-picker"}, opening}}
    {:ok, picker} = ImagePicker.update(opening, picker)
    picker
  end

  # The copy's reply, and what the picker's hook sends to the form from it
  defp reply(picker, copy) do
    origin = {picker.assigns.open_generation, picker.assigns.event_target, picker.assigns.pick_values}
    {:noreply, picker} = ImagePicker.handle_async(:pick_library_image, {:ok, {origin, {:ok, copy}}}, picker)

    [%{id: id, target: "3", values: values}] =
      for ["b:image_picker:pick", payload] <- Phoenix.LiveView.Utils.get_push_events(picker), do: payload

    Map.put(values, "id", to_string(id))
  end

  test "a thumbnail ready after the drawer moved on goes to the video it was picked for", ctx do
    %{user: user, page: page, video_a: video_a, video_b: video_b, thumbnail: thumbnail} = ctx

    {:noreply, _form} = Form.handle_event("browse_video_thumbnail", %{}, form_socket(page, user, video_a))
    params = picker(user) |> open_picker() |> reply(thumbnail)

    # The drawer shows video B by the time the copy is ready
    {:noreply, form} = Form.handle_event("select_image", params, form_socket(page, user, video_b))

    assert Brando.Repo.get!(Brando.Videos.Video, video_b.id).thumbnail_id == nil
    assert Brando.Repo.get!(Brando.Videos.Video, video_a.id).thumbnail_id == thumbnail.id
    assert form.assigns.edit_video.video.id == video_b.id
  end

  test "a thumbnail for the video in the drawer is set there", ctx do
    %{user: user, page: page, video_a: video_a, thumbnail: thumbnail} = ctx

    {:noreply, _form} = Form.handle_event("browse_video_thumbnail", %{}, form_socket(page, user, video_a))
    params = picker(user) |> open_picker() |> reply(thumbnail)

    {:noreply, form} = Form.handle_event("select_image", params, form_socket(page, user, video_a))

    assert form.assigns.edit_video.video.thumbnail_id == thumbnail.id
    assert Brando.Repo.get!(Brando.Videos.Video, video_a.id).thumbnail_id == thumbnail.id
  end
end
