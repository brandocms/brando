defmodule BrandoAdmin.Components.Form.DeliverTopicTest do
  # Regression coverage for D2 — the asset-delivery topic was minted per form
  # MOUNT, so an upload in flight across a remount broadcast its finished asset
  # to a topic nobody was listening on any more.
  #
  # Measured in e2e (2026-08-05): two successive mounts of one project form gave
  # `form:a852c2d1-…` then `form:dae79cd2-…`. The sticky UploadManager keeps
  # transferring across live navigation, and `put_intake_item/6` captured the
  # topic at intake and never updated it — so the mismatch is reachable by
  # ordinary use, and a PubSub broadcast to an empty topic is a silent `:ok`.
  #
  # The client now owns the topic (per-tab, per-entry, in sessionStorage) and
  # replays it on every mount.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 1]

  alias Brando.Factory
  alias BrandoAdmin.Components.Form
  alias Ecto.Changeset
  alias Phoenix.Component

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, user: user, page: page}
  end

  defp form_socket(ctx, deliver_topic) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:form, to_form(Changeset.change(ctx.page)))
    |> Component.assign(:entry, ctx.page)
    |> Component.assign(:entry_id, ctx.page.id)
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:singular, "page")
    |> Component.assign(:current_user, ctx.user)
    |> Component.assign(:deliver_topic, deliver_topic)
  end

  test "adopts the client's topic and subscribes to it", ctx do
    mount_topic = "form:" <> Ecto.UUID.generate()
    claimed = "form:" <> Ecto.UUID.generate()

    Phoenix.PubSub.subscribe(Brando.pubsub(), mount_topic)

    assert {:noreply, socket} =
             Form.handle_event(
               "set_deliver_topic",
               %{"topic" => claimed},
               form_socket(ctx, mount_topic)
             )

    assert socket.assigns.deliver_topic == claimed

    # Subscribed to the claimed topic...
    Phoenix.PubSub.broadcast(Brando.pubsub(), claimed, :delivered)
    assert_receive :delivered

    # ...and NOT still holding the mount-time one, or a form would accumulate a
    # subscription per remount and receive the same asset several times.
    Phoenix.PubSub.broadcast(Brando.pubsub(), mount_topic, :stale)
    refute_receive :stale, 50
  end

  test "re-claiming the topic it already has is a no-op", ctx do
    topic = "form:" <> Ecto.UUID.generate()

    assert {:noreply, socket} =
             Form.handle_event("set_deliver_topic", %{"topic" => topic}, form_socket(ctx, topic))

    assert socket.assigns.deliver_topic == topic
  end

  test "refuses a malformed topic and keeps the one it has", ctx do
    # The topic arrives from the client, and the subscribe side has to apply the
    # same rule intake does — a client free to name any topic could subscribe
    # its form to another form's deliveries, or to an unrelated PubSub channel.
    mount_topic = "form:" <> Ecto.UUID.generate()

    for bogus <- ["brando:modules", "form:not-a-uuid", "", "form:", nil, 42] do
      assert {:noreply, socket} =
               Form.handle_event(
                 "set_deliver_topic",
                 %{"topic" => bogus},
                 form_socket(ctx, mount_topic)
               )

      assert socket.assigns.deliver_topic == mount_topic
    end
  end

  test "the validation is the same one intake applies" do
    alias Brando.Uploads.AssetIntent

    topic = "form:" <> Ecto.UUID.generate()

    assert {:ok, ^topic} = AssetIntent.validate_deliver_topic(topic)
    assert {:error, _} = AssetIntent.validate_deliver_topic("brando:image:1")
    assert {:error, _} = AssetIntent.validate_deliver_topic("form:nope")
  end
end
