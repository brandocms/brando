defmodule Brando.Plug.I18nTest do
  use ExUnit.Case, async: true
  alias Brando.Plug.I18n

  test "put_locale" do
    mock_conn = %Plug.Conn{path_info: ["news"], private: %{plug_session: %{}}}
    conn = I18n.put_locale(mock_conn, Brando.Gettext)
    assert conn.assigns.language == "nb"
    assert conn.private.plug_session["language"] == "nb"

    mock_conn = %Plug.Conn{path_info: ["en", "news"], private: %{plug_session: %{"language" => "en"}}}
    conn = I18n.put_locale(mock_conn, Brando.Gettext)
    assert conn.assigns.language == "en"
    assert conn.private.plug_session["language"] == "en"
  end
end
