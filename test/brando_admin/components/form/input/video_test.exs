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

  defp update_socket(field, opts \\ []) do
    assigns = %{field: field, path: [], opts: opts, id: "video-input"}

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

  # A video's playback columns carry no default, so a new record has them all
  # nil. `Brando.HTML.Video` reads nil as "use the built-in default" — which is
  # `true` for `loop` and `false` for the rest — so the drawer's switches, which
  # are plain checkboxes, showed "off" for a video that loops. Field-level
  # defaults give the record real values, so the switches tell the truth.
  #
  # The plumbing for this existed on both ends (`edit_video.defaults`, and the
  # merge in `BrandoAdmin.Components.Form`) but nothing populated it: the
  # generic input renderer passes a fixed assign list that has no `defaults` in
  # it, so `assign_new` always won with `%{}`.
  describe "field-level defaults" do
    test "default to empty when the form input declares none" do
      socket = update_socket(video_field(nil))

      assert socket.assigns.defaults == %{}
    end

    test "are read from the form input's opts" do
      socket = update_socket(video_field(nil), defaults: %{loop: true, muted: true})

      assert socket.assigns.defaults == %{loop: true, muted: true}
    end

    # `Kernel.struct/2` would drop an unknown key without a word and the field
    # would go on rendering its built-in default — the same silent-drop shape
    # this whole area just got fixed for.
    test "raise on a key the video schema cannot hold" do
      assert_raise ArgumentError, ~r/no field on Brando.Videos.Video for \[:looop\]/, fn ->
        update_socket(video_field(nil), defaults: %{looop: true})
      end
    end

    test "raise when not given a map" do
      assert_raise ArgumentError, ~r/must be a map/, fn ->
        update_socket(video_field(nil), defaults: [loop: true])
      end
    end
  end

  # The defaults land on the video *record*, which is the middle layer of the
  # resolution chain. A block or `{% video %}` override still wins over them.
  describe "field defaults vs render-time overrides" do
    test "a block override beats the field default" do
      video = %Brando.Videos.Video{
        type: :external_file,
        source_url: "/x.mp4",
        width: 100,
        height: 100,
        loop: true
      }

      assert render_video(video, []) =~ " loop"
      refute render_video(video, loop: false) =~ " loop"
    end

    defp render_video(video, opts) do
      assigns = %{video: video, opts: opts}

      Phoenix.LiveViewTest.rendered_to_string(
        Phoenix.LiveView.TagEngine.component(
          &Brando.HTML.Video.video/1,
          assigns,
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )
      )
    end
  end
end
