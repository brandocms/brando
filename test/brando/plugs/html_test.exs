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
    conn = HTML.put_css_classes(mock_conn, ["class", "class2", "class3"])
    assert conn.private.brando_css_classes == "class class2 class3"
    conn = HTML.put_css_classes(mock_conn, 5)
    assert conn.private == %{plug_session: %{}}
  end

  test "put_title" do
    mock_conn = %Plug.Conn{assigns: %{}}
    conn = HTML.put_title(mock_conn, "Title")
    assert conn.assigns.page_title == "Title"
  end

end
