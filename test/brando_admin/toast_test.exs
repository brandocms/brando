defmodule BrandoAdmin.ToastTest do
  use ExUnit.Case, async: false

  alias Brando.Content.Identifier
  alias Phoenix.Socket.Broadcast

  test "a mutation toast reaches the lobby as JSON the admin socket can send" do
    Brando.endpoint().subscribe("lobby")
    on_exit(fn -> Brando.endpoint().unsubscribe("lobby") end)

    identifier = %Identifier{
      entry_id: 1,
      schema: Brando.Pages.Page,
      title: "Index",
      status: :published,
      language: :en,
      url: "/",
      updated_at: ~U[2026-10-17 17:10:20Z]
    }

    Brando.Notifications.push_mutation("updated", identifier, :system)

    assert_receive %Broadcast{topic: "lobby", event: "toast", payload: payload}

    # What BrandoAdmin.LobbyChannel pushes, through the socket's JSON serializer.
    sent = payload |> Map.delete(:authorization) |> Jason.encode!() |> Jason.decode!()

    assert %{"type" => "mutation", "payload" => %{"action" => "updated", "identifier" => sent_identifier}} = sent
    assert %{"entry_id" => 1, "title" => "Index", "type" => _, "updated_at" => "2026-10-17T17:10:20Z"} = sent_identifier
  end
end
