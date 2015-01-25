defmodule Brando.MenuTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule Menu do
    @moduledoc """
    Menu definitions for the Admin/dashboard Menu. See `Brando.Menu` docs for
    more information
    """
    use Brando.Menu

    menu "Test",
      %{name: "Test", anchor: "test", bgcolor: "#fffffff", icon: "icon",
        submenu: [%{name: "Name", url: "/url"}]}
  end

  test "menu" do
    assert Menu.get_menu ==
      %{anchor: "test", bgcolor: "#fffffff", icon: "icon", name: "Test", submenu: [%{name: "Name", url: "/url"}]}
  end
end