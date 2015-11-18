defmodule Brando.Plug.HTMLTest do
  use ExUnit.Case, async: true
  alias Brando.Plug.HTML

  test "put_section" do
    mock_conn = %Plug.Conn{private: %{plug_session: %{}}}
    conn = HTML.put_section(mock_conn, "section-name")
    assert conn.private.brando_section_name == "section-name"
  end

  test "put_css_classes" do
    mock_conn = %Plug.Conn{private: %{plug_session: %{}}}
    conn = HTML.put_css_classes(mock_conn, "class class2")
    assert conn.private.brando_css_classes == "class class2"
  end
end
