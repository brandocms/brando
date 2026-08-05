defmodule BrandoAdmin.Components.Form.Input.VideoTest do
  # Regression coverage for the video input's asset lookup.
  #
  # `update/2` used to hard-match `{:ok, video} = Brando.Videos.get_video(...)`
  # at four sites. A referenced-but-hard-deleted video — or the nil `video_id`
  # on the path-lookup branch — raised MatchError and destroyed the entire entry
  # form LiveView process, taking every unsaved change with it.
  # `input/image.ex` already guarded this with a `case`.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Input
  alias Ecto.Changeset

  # A Ref carries `video_id` + a `:video` belongs_to, which is the shape the
  # input reads (`String.to_existing_atom("#{field}_id")`).
  defp video_field(video_id) do
    changeset =
      %Brando.Content.Ref{}
      |> Changeset.change(%{name: "video_ref", uid: "vidref0001"})
      |> Changeset.put_change(:video_id, video_id)

    to_form(changeset, as: :ref)[:video]
  end

  defp update_socket(field) do
    assigns = %{field: field, path: [], opts: [], id: "video-input"}

    {:ok, socket} =
      %Phoenix.LiveView.Socket{}
      |> Input.Video.mount()
      |> then(fn {:ok, socket} -> Input.Video.update(assigns, socket) end)

    socket
  end

  test "renders the empty picker state when the referenced video was hard-deleted" do
    video = Factory.insert(:video)
    deleted_id = video.id
    Brando.Repo.delete!(video)

    socket = update_socket(video_field(deleted_id))

    assert socket.assigns.video == nil
    assert socket.assigns.video_id == nil
  end

  test "renders the empty picker state when video_id is nil" do
    socket = update_socket(video_field(nil))

    assert socket.assigns.video == nil
    assert socket.assigns.video_id == nil
  end

  test "loads a video that does exist" do
    video = Factory.insert(:video)

    socket = update_socket(video_field(video.id))

    assert socket.assigns.video.id == video.id
    assert socket.assigns.video_id == video.id
  end

  test "a hard-deleted video renders instead of crashing" do
    video = Factory.insert(:video)
    deleted_id = video.id
    Brando.Repo.delete!(video)

    html =
      render_component(&Input.Video.video_preview/1,
        video: nil,
        field: video_field(deleted_id),
        relation_field: to_form(Changeset.change(%Brando.Content.Ref{}), as: :ref)[:video_id],
        click: false,
        editable: true
      )

    assert html =~ "No video associated with field"
  end
end
