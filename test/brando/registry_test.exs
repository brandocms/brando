defmodule Brando.RegistryTest do
  use ExUnit.Case
  alias Brando.Registry

  setup do
    Registry.wipe()
    :ok
  end

  test "empty state" do
    assert Registry.state() == %Registry.State{}
  end

  test "register unknown modules fails" do
    assert_raise Brando.Exception.RegistryError, fn ->
      Registry.register(Fakemodule, [:menu])
    end
    assert_raise Brando.Exception.RegistryError, fn ->
      Registry.register(Fakemodule, [:gettext])
    end
  end

  test "register menu modules" do
    assert Registry.register(Brando.Users, [:menu])
           == %Brando.Registry.State{gettext_modules: [],
                                     menu_modules: [Brando.Users.Menu]}

    assert Registry.register(Brando.Images, [:menu])
           == %Brando.Registry.State{gettext_modules: [],
                                     menu_modules: [Brando.Images.Menu, Brando.Users.Menu]}

    assert Registry.menu_modules()
           == [Brando.Users.Menu, Brando.Images.Menu]

    Registry.wipe()

    assert Registry.menu_modules()
           == []
  end

  test "register gettext module" do
    assert Registry.register(Brando, [:gettext])
           == %Brando.Registry.State{gettext_modules: [Brando.Gettext],
                                     menu_modules: []}
    assert Registry.gettext_modules()
           == [Brando.Gettext]

    Registry.wipe()

    assert Registry.gettext_modules()
           == []
  end

  # test "add entry to registry" do
  #   assert Registry.register("user", Brando.UserForm, "Create user", [:id, :username])
  #          == %Registry.State{forms: %{"user" => {Brando.UserForm,
  #                                      "Create user", [:id, :username]}}}
  # end
  #
  # test "get entry from registry" do
  #   Registry.register("user", Brando.UserForm, "Create user", [:id, :username])
  #   assert Registry.get("user") == {:ok, {Brando.UserForm, "Create user", [:id, :username]}}
  # end
  #
  # test "wipe registry" do
  #   Registry.register("user", Brando.UserForm, "Create user", [:id, :username])
  #   assert Registry.get("user") == {:ok, {Brando.UserForm, "Create user", [:id, :username]}}
  #   Registry.wipe()
  #   assert Registry.state() == %Registry.State{forms: %{}}
  # end
end
