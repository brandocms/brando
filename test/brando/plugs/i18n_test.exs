defmodule Brando.Plug.I18nTest do
  use ExUnit.Case
  use Brando.ConnCase
  alias Brando.Plug.I18n
  alias Brando.Factory

  test "put_locale" do
    mock_conn = %Plug.Conn{path_info: ["news"], private: %{plug_session: %{}}}
    conn = I18n.put_locale(mock_conn, [])
    assert conn.assigns.language == "en"
    assert conn.private.plug_session["language"] == "en"

    mock_conn = %Plug.Conn{
      path_info: ["en", "news"],
      private: %{plug_session: %{"language" => "en"}}
    }

    conn = I18n.put_locale(mock_conn, [])
    assert conn.assigns.language == "en"
    assert conn.private.plug_session["language"] == "en"

    mock_conn = %Plug.Conn{
      path_info: ["no", "nyheter"],
      private: %{plug_session: %{"language" => "no"}}
    }

    conn = I18n.put_locale(mock_conn, [])
    assert conn.assigns.language == "no"
    assert conn.private.plug_session["language"] == "no"
  end

  test "put_locale host_map" do
    opts = [by_host: %{"myapp.se" => "se", "myapp.dk" => "dk"}]
    mock_conn_se = %Plug.Conn{host: "myapp.se", path_info: ["/"], private: %{plug_session: %{}}}
    mock_conn_dk = %Plug.Conn{host: "myapp.dk", path_info: ["/"], private: %{plug_session: %{}}}
    conn = I18n.put_locale(mock_conn_se, opts)
    assert conn.assigns.language == "se"
    assert conn.private.plug_session["language"] == "se"
    conn = I18n.put_locale(mock_conn_dk, opts)
    assert conn.assigns.language == "dk"
    assert conn.private.plug_session["language"] == "dk"
  end

  test "put_admin_locale returns default when no current_user" do
    mock_conn = %Plug.Conn{path_info: ["news"], private: %{plug_session: %{}}}
    _conn = I18n.put_admin_locale(mock_conn, [])
    assert Gettext.get_locale(Brando.Gettext) == "en"
  end

  test "put_admin_locale returns current_user's language" do
    u1 = Factory.insert(:random_user, language: "en")

    mock_conn = %Plug.Conn{
      path_info: ["news"],
      private: %{plug_session: %{}},
      assigns: %{current_user: u1}
    }

    _conn = I18n.put_admin_locale(mock_conn, [])
    assert Gettext.get_locale(Brando.Gettext) == "en"
  end
end
