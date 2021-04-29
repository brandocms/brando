defmodule Brando.Plug.I18nTest do
  use ExUnit.Case
  use Brando.ConnCase
  alias Brando.Plug.I18n
  alias Brando.Factory

  test "put_locale" do
    mock_conn = %Plug.Conn{path_info: ["news"], private: %{plug_session: %{}}}
    conn = I18n.put_locale(mock_conn, [])
    assert conn.assigns.language == "no"
    assert conn.private.plug_session["language"] == "no"

    mock_conn = %Plug.Conn{
      path_info: ["en", "news"],
      private: %{plug_session: %{"language" => "en"}}
    }

    conn = I18n.put_locale(mock_conn, [])
    assert conn.assigns.language == "en"
    assert conn.private.plug_session["language"] == "en"
  end

  test "put_admin_locale" do
    u1 = Factory.insert(:random_user, language: "en")
    mock_conn = %Plug.Conn{path_info: ["news"], private: %{plug_session: %{}}}
    _conn = I18n.put_admin_locale(mock_conn, [])
    assert Gettext.get_locale(Brando.Gettext) == "no"

    mock_conn = %Plug.Conn{
      path_info: ["en", "news"]
    }

    mock_conn = put_private(mock_conn, :guardian_default_resource, u1)

    _conn = I18n.put_admin_locale(mock_conn, [])
    assert Gettext.get_locale(Brando.Gettext) == "en"
  end
end
