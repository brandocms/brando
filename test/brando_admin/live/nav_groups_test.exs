defmodule BrandoAdmin.NavGroupsTest do
  # Configuration's sidebar submenu lists its screens under small headings,
  # each group labelled by its heading. Groups with nothing the user may open
  # show no heading.
  use Brando.LiveCase

  @groups ~w(site publishing building_blocks operations)

  test "a superuser gets the four groups, each labelled by its heading", %{conn: conn} do
    nav = nav(conn)

    for key <- @groups do
      id = "nav-group-configuration-#{key}"
      assert has_element?(nav, "[data-menu-key='configuration'] dd .nav-group[role='group'][aria-labelledby='#{id}']")
      assert has_element?(nav, ".nav-group[aria-labelledby='#{id}'] > h4##{id}.nav-group-label")
      # The heading is a label, not a link
      refute has_element?(nav, "##{id} a")
    end

    html = nav |> element("[data-menu-key='configuration'] dd") |> render()
    positions = Enum.map(@groups, &(:binary.match(html, "nav-group-configuration-#{&1}") |> elem(0)))
    assert positions == Enum.sort(positions)

    assert has_element?(nav, "[aria-labelledby='nav-group-configuration-site'] li a[href='/admin/config/seo']")

    assert has_element?(
             nav,
             "[aria-labelledby='nav-group-configuration-building_blocks'] li a[href='/admin/config/content/modules']"
           )

    assert has_element?(nav, "[aria-labelledby='nav-group-configuration-operations'] li a[href='/admin/config/utils']")
  end

  test "an editor sees only the groups with screens they may open", %{conn: conn} do
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    nav = conn |> recycle() |> log_in_user(editor) |> nav()

    assert has_element?(nav, "#nav-group-configuration-site")
    assert has_element?(nav, "#nav-group-configuration-publishing")
    refute has_element?(nav, "#nav-group-configuration-building_blocks")
    refute has_element?(nav, "#nav-group-configuration-operations")
    refute has_element?(nav, "a[href='/admin/config/content/modules']")
  end

  test "other submenus keep a plain list", %{conn: conn} do
    nav = nav(conn)

    assert has_element?(nav, "dd > ul > li > a[href='/admin/assets/images']")
    refute has_element?(nav, "dd:has(a[href='/admin/assets/images']) .nav-group")
  end

  defp nav(conn) do
    {:ok, view, _html} = live(conn, "/admin/pages")
    find_live_child(view, "brando-nav")
  end
end
