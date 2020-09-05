defmodule Brando.UserChannelTest do
  use Brando.ChannelCase
  use ExUnit.Case

  alias Brando.Factory
  alias Brando.UserChannel
  alias BrandoIntegration.AdminSocket
  alias BrandoIntegrationWeb.Endpoint

  @endpoint Endpoint

  setup do
    user = Factory.insert(:random_user)
    socket = socket(AdminSocket, "user", %{})
    socket = Guardian.Phoenix.Socket.put_current_resource(socket, user)
    {:ok, socket} = AdminSocket.connect(%{"guardian_token" => "blerg"}, socket)
    {:ok, _, socket} = subscribe_and_join(socket, UserChannel, "user:#{user.id}", %{})

    {:ok, %{socket: socket, user: user}}
  end

  test "alert", %{user: user} do
    UserChannel.alert(user, "hello!")
    assert_broadcast "alert", %{message: "hello!"}
  end

  test "handle_out alert", %{socket: socket} do
    broadcast_from(socket, "alert", %{message: "hello!"})
    assert_push "alert", %{message: "hello!"}
  end

  test "set_progress", %{user: user} do
    UserChannel.set_progress(user, 50)
    assert_broadcast "set_progress", %{value: 50}
  end

  test "handle_out set_progress", %{socket: socket} do
    broadcast_from(socket, "set_progress", %{value: 50})
    assert_push "set_progress", %{value: 50}
  end

  test "increase_progress", %{user: user} do
    UserChannel.increase_progress(user, 100)
    assert_broadcast "increase_progress", %{value: 100}
  end

  test "handle_out increase_progress", %{socket: socket} do
    broadcast_from(socket, "increase_progress", %{value: 100})
    assert_push "increase_progress", %{value: 100}
  end

  # test "images:delete_images", %{socket: socket} do
  #   i1 = Factory.insert(:image)
  #   i2 = Factory.insert(:image)
  #   ids = [i1.id, i2.id]

  #   ref = push(socket, "images:delete_images", %{"ids" => ids})
  #   assert_reply ref, :ok, %{code: 200, ids: ids}
  # end
end
