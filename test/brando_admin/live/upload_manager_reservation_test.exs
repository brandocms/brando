defmodule BrandoAdmin.UploadManagerReservationTest do
  @moduledoc """
  An assistant conversation names attachments in the order the user chose
  them. The manager announces the accepted files at intake — before any of
  them completes — and delivers each asset with its file's ref.
  """
  use Brando.LiveCase

  test "intake announces accepted files in selection order", %{conn: conn} do
    topic = "form:#{Ecto.UUID.generate()}"
    Phoenix.PubSub.subscribe(Brando.pubsub(), topic)
    {:ok, view, _html} = live(conn, "/admin/assistant")
    manager = find_live_child(view, "brando-upload-manager-lv")

    render_hook(manager, "intake", %{
      "files" => [
        %{"index" => 0, "name" => "large.jpg", "size" => 9_000_000, "type" => "image/jpeg"},
        %{"index" => 1, "name" => "small.jpg", "size" => 1_000, "type" => "image/jpeg"}
      ],
      "target" => %{
        "kind" => "ai_conversation",
        "component_id" => "assistant",
        "asset_type" => "image",
        "config_target" => "default",
        "deliver_topic" => topic
      }
    })

    assert_receive {:assets_reserved, %{"kind" => "ai_conversation"},
                    [%{filename: "large.jpg", ref: first}, %{filename: "small.jpg", ref: second}]}

    assert is_binary(first) and is_binary(second) and first != second
  end
end
