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
      Registry.register(Fakemodule, [:gettext])
    end
  end

  test "register gettext module" do
    assert Registry.register(Brando, [:gettext])
           == %Brando.Registry.State{gettext_modules: [Brando.Gettext]}
    assert Registry.gettext_modules()
           == [Brando.Gettext]

    Registry.wipe()

    assert Registry.gettext_modules()
           == []
  end
end
