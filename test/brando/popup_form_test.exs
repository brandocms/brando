defmodule Brando.PopupFormTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  alias Brando.PopupForm.Registry
  alias Brando.Factory

  setup do
    Registry.wipe()
    Registry.register(:accounts, "user", Brando.UserForm, "Create user", [:id, :username])
    :ok
  end

  test "create" do
    form = Brando.PopupForm.create("accounts", [])
    assert form.changeset.errors[:username]
    assert form.schema == Brando.User
    assert form.source == "user"
    assert form.type == :create
  end

  test "post" do
    user_params =
      :user
      |> Factory.params_for(%{avatar: nil})
      |> Map.put(:role, 5)

    user_params = Plug.Conn.Query.encode(%{"user" => user_params})
    {:ok, {user, fields_to_return}} = Brando.PopupForm.post("accounts", user_params, %Phoenix.Socket{})

    assert user.email == "james@thestooges.com"
    assert fields_to_return == [:id, :username]
  end
end
