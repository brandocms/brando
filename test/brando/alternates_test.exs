defmodule Brando.AlternatesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  test "creates has_alternates?" do
    assert {:has_alternates?, 0} in Page.__info__(:functions)
  end

  test "linking and unlinking entries" do
    usr = Factory.insert(:random_user)

    {:ok, p1} =
      Pages.create_page(
        Factory.params_for(:page, title: "Title English", language: :en),
        usr
      )

    {:ok, p2} =
      Pages.create_page(
        Factory.params_for(:page, title: "Tittel Norsk", language: :no),
        usr
      )

    Page.Alternate.add(p1.id, p2.id)

    {:ok, p1} = Pages.get_page(%{matches: %{id: p1.id}, preload: [:alternate_entries]})
    {:ok, p2} = Pages.get_page(%{matches: %{id: p2.id}, preload: [:alternate_entries]})

    assert Enum.count(p1.alternate_entries) == 1
    assert Enum.count(p2.alternate_entries) == 1

    p1_alts = Enum.map(p1.alternate_entries, & &1.id)
    p2_alts = Enum.map(p2.alternate_entries, & &1.id)

    assert p2.id in p1_alts
    refute p1.id in p1_alts
    assert p1.id in p2_alts
    refute p2.id in p2_alts

    Page.Alternate.delete(p1.id, p2.id)

    {:ok, p1} = Pages.get_page(%{matches: %{id: p1.id}, preload: [:alternate_entries]})
    {:ok, p2} = Pages.get_page(%{matches: %{id: p2.id}, preload: [:alternate_entries]})

    assert p1.alternate_entries == []
    assert p2.alternate_entries == []
  end

  test "a page without a URL gets no canonical or alternates of its own" do
    usr = Factory.insert(:random_user)

    {:ok, en} =
      Pages.create_page(Factory.params_for(:page, title: "Not found", uri: "404", language: :en, has_url: false), usr)

    {:ok, no} =
      Pages.create_page(Factory.params_for(:page, title: "Ikke funnet", uri: "404", language: :no, has_url: false), usr)

    Page.Alternate.add(en.id, no.id)
    {:ok, en} = Pages.get_page(%{matches: %{id: en.id}, preload: [:alternate_entries]})

    conn = Brando.Plug.HTML.put_hreflang(%Plug.Conn{assigns: %{}, request_path: "en/missing"}, en)
    refute Map.has_key?(conn.private, :brando_hreflangs)

    assigns = %{conn: conn}

    assert rendered_to_string(~H"<Brando.HTML.render_hreflangs conn={@conn} />") =~
             ~s(<link rel="canonical" href="http://localhost/en/missing">)
  end

  test "an alternate without a URL is skipped without an error" do
    usr = Factory.insert(:random_user)

    {:ok, public} =
      Pages.create_page(Factory.params_for(:page, title: "Public", uri: "public0", language: :en), usr)

    {:ok, hidden} =
      Pages.create_page(Factory.params_for(:page, title: "Skjult", uri: "public0", language: :no, has_url: false), usr)

    Page.Alternate.add(public.id, hidden.id)
    {:ok, public} = Pages.get_page(%{matches: %{id: public.id}, preload: [:alternate_entries]})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn = Brando.Plug.HTML.put_hreflang(%Plug.Conn{assigns: %{}}, public)
        assert conn.private.brando_hreflangs == [{:en, "http://localhost/en/public0"}]
      end)

    refute log =~ "No valid url found"
  end

  test "put_hreflang and render_hreflang" do
    usr = Factory.insert(:random_user)

    {:ok, p1} =
      Pages.create_page(
        Factory.params_for(:page, title: "Title English", uri: "test0", language: :en),
        usr
      )

    {:ok, p2} =
      Pages.create_page(
        Factory.params_for(:page, title: "Tittel Norsk", uri: "test0", language: :no),
        usr
      )

    Page.Alternate.add(p1.id, p2.id)

    {:ok, p1} = Pages.get_page(%{matches: %{id: p1.id}, preload: [:alternate_entries]})

    mock_conn = %Plug.Conn{assigns: %{}}
    mock_conn = Brando.Plug.HTML.put_hreflang(mock_conn, p1)

    assert {:en, "http://localhost/en/test0"} in mock_conn.private.brando_hreflangs
    assert {:no, "http://localhost/no/test0"} in mock_conn.private.brando_hreflangs

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <Brando.HTML.render_hreflangs conn={@mock_conn} />
    """

    assert rendered_to_string(comp) =~
             "<link rel=\"canonical\" href=\"http://localhost/en/test0\">\n<link rel=\"alternate\" href=\"http://localhost/en/test0\" type=\"text/html\" hreflang=\"en\"><link rel=\"alternate\" href=\"http://localhost/no/test0\" type=\"text/html\" hreflang=\"no\">"

    mock_conn = %Plug.Conn{assigns: %{}, request_path: "en/test0"}

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <Brando.HTML.render_hreflangs conn={@mock_conn} />
    """

    assert rendered_to_string(comp) =~
             "<link rel=\"canonical\" href=\"http://localhost/en/test0\">"
  end
end
