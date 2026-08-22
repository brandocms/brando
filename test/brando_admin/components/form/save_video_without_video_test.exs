defmodule BrandoAdmin.Components.Form.SaveVideoWithoutVideoTest do
  @moduledoc """
  The video drawer can be saved before there is anything to save: opened on a
  field with no video, nothing picked and nothing uploaded, and the editor hits
  save. `edit_video.video` is nil then.

  `save_video_authorized` bound that nil straight into
  `Brando.Videos.Video.changeset/3`, where `Brando.Blueprint.ChangesetRunner.run/1`
  reads `changeset_params.schema.__struct__` — so nil raised

      ** (KeyError) key :__struct__ not found in: nil

  out of `handle_event/3`, which kills the entry form process and every unsaved
  change the editor was holding. Seen in production three times, the payload
  each time being `video[type]=upload` against an empty drawer.

  `validate_video/2` has always guarded this (`edit_video.video || %Video{}`);
  only the save path had not. Defaulting the same way here would not have been
  right either — `update_video/2` further down expects a persisted record — so
  the drawer simply closes, which is what the sibling "no video in params"
  clause already did.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias BrandoAdmin.Components.Form
  alias Phoenix.Component

  setup do
    {:ok, user: Brando.Factory.insert(:random_user)}
  end

  defp drawer_socket(user, edit_video) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:current_user, user)
    |> Component.assign(:edit_video, edit_video)
    |> Component.assign(:edit_image, %{})
    |> Component.assign(:edit_file, %{})
    |> Component.assign(:editing_video?, true)
    |> Component.assign(:editing_image?, false)
    |> Component.assign(:editing_file?, false)
    |> Component.assign(:video_changeset, nil)
  end

  test "saving an empty drawer closes it instead of killing the form", ctx do
    socket =
      drawer_socket(ctx.user, %{
        video: nil,
        path: [],
        field: :video,
        relation_field: nil,
        schema: Brando.Pages.Page
      })

    # The production payload, verbatim.
    assert {:noreply, socket} =
             Form.handle_event("save_video", %{"video" => %{"type" => "upload"}}, socket)

    refute socket.assigns.editing_video?, "the drawer stayed open"

    refute socket.assigns.video_save_authorized?,
           "the authorization flag was left set for the next event"
  end

  test "an empty drawer carrying an external url is still refused first", ctx do
    # The external-url gate runs before the nil check, and must keep doing so —
    # closing the drawer is a fallback for having nothing to save, not a way
    # around a field that disallows external videos.
    socket =
      drawer_socket(ctx.user, %{
        video: nil,
        path: [],
        field: :video,
        relation_field: nil,
        # Not a real asset field, so `external_video_urls_allowed?/1` rescues
        # to false — the same answer a field configured with
        # `allow_external_urls: false` gives.
        schema: __MODULE__
      })

    assert {:noreply, socket} =
             Form.handle_event(
               "save_video",
               %{"video" => %{"type" => "youtube", "remote_id" => "abc"}},
               socket
             )

    assert socket.assigns.editing_video?,
           "the drawer closed on a refused external url, which reads as a successful save"
  end
end
