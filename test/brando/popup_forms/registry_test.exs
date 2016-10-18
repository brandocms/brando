defmodule Brando.PopupForm.RegistryTest do
  use ExUnit.Case
  alias Brando.PopupForm.Registry

  setup do
    Registry.wipe()
    :ok
  end

  test "empty state" do
    assert Registry.state() == %Registry.State{forms: %{}}
  end

  test "add entry to registry" do
    assert Registry.register("user", Brando.UserForm, "Create user", [:id, :username])
           == %Registry.State{forms: %{"user" => {Brando.UserForm,
                                       "Create user", [:id, :username]}}}
  end

  test "get entry from registry" do
    Registry.register("user", Brando.UserForm, "Create user", [:id, :username])
    assert Registry.get("user") == {:ok, {Brando.UserForm, "Create user", [:id, :username]}}
  end

  test "wipe registry" do
    Registry.register("user", Brando.UserForm, "Create user", [:id, :username])
    assert Registry.get("user") == {:ok, {Brando.UserForm, "Create user", [:id, :username]}}
    Registry.wipe()
    assert Registry.state() == %Registry.State{forms: %{}}
  end
end
