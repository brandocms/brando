defmodule Brando.Plug.HTMLTest do
  use ExUnit.Case, async: true
  alias Brando.Plug.HTML

  describe "put_json_ld/3 with :entities" do
    setup do
      %{conn: %Plug.Conn{private: %{plug_session: %{}}, assigns: %{}}}
    end

    test "attaches pre-built nodes that have no entry to derive from", %{conn: conn} do
      service = Brando.JSONLD.Schema.Service.build(%{name: "Identitetsdesign"})

      conn = HTML.put_json_ld(conn, :entities, service)

      assert conn.assigns.json_ld_entities == [service]
    end

    test "appends rather than replacing, so calls compose", %{conn: conn} do
      a = Brando.JSONLD.Schema.Service.build(%{name: "A"})
      b = Brando.JSONLD.Schema.Service.build(%{name: "B"})
      c = Brando.JSONLD.Schema.Service.build(%{name: "C"})

      conn =
        conn
        |> HTML.put_json_ld(:entities, a)
        |> HTML.put_json_ld(:entities, [b, c])

      assert conn.assigns.json_ld_entities == [a, b, c]
    end
  end

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
