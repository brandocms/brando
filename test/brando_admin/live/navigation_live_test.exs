defmodule BrandoAdmin.NavigationLiveTest do
  # Editing a menu's items in the admin, and what the site's navigation shows
  # afterwards. These were browser tests
  # (e2e/playwright/tests/configuration/navigation.spec.js). The menu form is
  # server-rendered, and the site renders its menu from the navigation cache
  # with `Brando.HTML.menu/1`, which is what the checks below render.
  # Reordering by dragging stays in the browser.
  use Brando.LiveCase

  import Phoenix.Component, only: [sigil_H: 2]

  alias Brando.Content.Var
  alias Brando.Navigation.Item
  alias Brando.Navigation.Menu

  setup %{current_user: user} do
    # The site reads menus from a cache; drop it so the next test reloads it.
    on_exit(fn -> Brando.Cache.del(:navigation) end)

    menu =
      Repo.insert!(%Menu{
        creator_id: user.id,
        key: "main",
        language: :en,
        sequence: 0,
        status: :published,
        title: "Main menu",
        items: [
          item("brando", "Brando CMS", "https://brandocms.com", user),
          item("documentation", "API Documentation", "https://hexdocs.pm/brando", user),
          item("guides", "Guides", "https://brandocms.com/guides", user)
        ]
      })

    Brando.Cache.Navigation.set()
    %{menu: menu}
  end

  defp item(key, text, url, user) do
    %Item{
      key: key,
      status: :published,
      creator_id: user.id,
      link: %Var{
        type: :link,
        link_type: :url,
        creator_id: user.id,
        link_text: text,
        link_target_blank: true,
        placement: :content,
        label: "Link",
        key: "link",
        value: url
      }
    }
  end

  # The site's navigation as the frontend layout renders it.
  defp site_menu do
    conn =
      Phoenix.ConnTest.build_conn(:get, "/")
      |> Brando.Plug.Navigation.call(key: "main", as: :navigation)

    assigns = %{conn: conn, navigation: conn.assigns.navigation}

    ~H"""
    <ul>
      <Brando.HTML.menu :let={item} menu={@navigation}>
        <li>
          <Brando.HTML.menu_item :let={text} conn={@conn} item={item}>{text}</Brando.HTML.menu_item>
        </li>
      </Brando.HTML.menu>
    </ul>
    """
    |> rendered_to_string()
    |> Floki.parse_fragment!()
    |> Floki.find("[data-menu-item-key]")
    |> Map.new(&{hd(Floki.attribute(&1, "data-menu-item-key")), String.trim(Floki.text(&1))})
  end

  defp open(conn, menu) do
    {:ok, list, _html} = live(conn, "/admin/config/navigation/menus")
    render_async(list)
    assert has_element?(list, "a[href='/admin/config/navigation/menus/update/#{menu.id}']", "Main menu")

    {view, _html} = live_form(conn, "/admin/config/navigation/menus/update/#{menu.id}", "menu_form")
    view
  end

  defp save(view, params \\ %{}) do
    view |> form("#menu_form_form", params) |> render_submit()
    assert_redirect(view, "/admin/config/navigation/menus", 3_000)
  end

  test "a deactivated menu item leaves the site's navigation", %{conn: conn, menu: menu} do
    assert site_menu()["guides"] == "Guides"
    view = open(conn, menu)

    assert has_element?(view, "#status-dropdown-menu_items_2_status label", "Deactivated")
    save(view, %{"menu" => %{"items" => %{"2" => %{"status" => "disabled"}}}})

    refute Map.has_key?(site_menu(), "guides")
    assert site_menu()["documentation"] == "API Documentation"
  end

  test "a new menu item gets a key from its link text, and the site shows it", %{conn: conn, menu: menu} do
    view = open(conn, menu)

    view |> element("#menu_form_form button", "Add entry") |> render_click()
    assert has_element?(view, "#var-menu_items_3_link_0-link-config input[type=radio][value=url]")

    link = %{
      "link_type" => "url",
      "value" => "https://google.com",
      "link_text" => "Google",
      "link_target_blank" => "true"
    }

    view |> form("#menu_form_form", %{"menu" => %{"items" => %{"3" => %{"link" => link}}}}) |> render_change()

    field = view |> element("#menu_items_3_link_0_identifier_id-field-base") |> render()
    assert field =~ "Google"
    assert field =~ "https://google.com"

    # Until set, the key follows the link text.
    assert view |> element("#menu_items_3_key-disclosure .disclosed-text-summary code") |> render() =~ ">google<"

    save(view, %{"menu" => %{"items" => %{"3" => %{"key" => "new_item", "link" => link}}}})

    assert site_menu()["new_item"] == "Google"
  end

  test "a removed menu item leaves the site's navigation", %{conn: conn, menu: menu} do
    assert site_menu()["brando"] == "Brando CMS"
    view = open(conn, menu)

    # "Remove entry" dispatches a change carrying its own name and value.
    assert has_element?(view, "button[name='menu[drop_items_ids][]'][value='0']")
    view |> element("#menu_form_form") |> render_change(%{"menu" => %{"drop_items_ids" => ["0"]}})
    refute has_element?(view, "input[name='menu[items][2][key]']")
    save(view)

    refute Map.has_key?(site_menu(), "brando")
    assert Map.keys(site_menu()) |> Enum.sort() == ["documentation", "guides"]
  end

  # Two clicks on "Add entry" that both reach the server before the form has
  # re-rendered the subform. Each click is handled by the subform with the
  # form as it last rendered it; when each built the whole changeset from
  # that copy, the second overwrote the first and one row was lost.
  test "two quick clicks on Add entry add two rows", %{conn: conn, menu: menu} do
    view = open(conn, menu)
    refute has_element?(view, "input[name='menu[items][3][key]']")

    view |> element("#menu_form_form button", "Add entry") |> then(&queue_clicks(view, &1))

    assert has_element?(view, "input[name='menu[items][3][key]']")
    assert has_element?(view, "input[name='menu[items][4][key]']")
    refute has_element?(view, "input[name='menu[items][5][key]']")
  end

  # A saved item the editor removes stays in the changeset, marked for
  # removal. Writing it back with the next add raised "cannot replace
  # related" and took the LiveView down; it also shifted every position after
  # it, so an insert landed one row off.
  test "an item can be added and inserted after a saved one is removed", %{conn: conn, menu: menu} do
    view = open(conn, menu)

    view |> element("#menu_form_form") |> render_change(%{"menu" => %{"drop_items_ids" => ["0"]}})
    refute has_element?(view, "input[name='menu[items][2][key]']")

    view |> element("#menu_form_form button", "Add entry") |> render_click()
    settle(view)
    assert has_element?(view, "input[name='menu[items][1][key]'][value='guides']")
    assert has_element?(view, "input[name='menu[items][2][key]']")
    refute has_element?(view, "input[name='menu[items][3][key]']")

    # + above "guides", the second row
    view
    |> element(~s(#menu_form_form button[phx-click*="insert_subentry"][phx-click*='"index":1']))
    |> render_click()

    settle(view)
    assert has_element?(view, "input[name='menu[items][0][key]'][value='documentation']")
    assert has_element?(view, "input[name='menu[items][2][key]'][value='guides']")
    assert has_element?(view, "input[name='menu[items][3][key]']")
  end

  # An add changes the form without a round trip through the browser, so the
  # form has to tell the other editors itself that the items have changed.
  test "other editors are told the items changed after an add", %{conn: conn, menu: menu} do
    view = open(conn, menu)
    Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("dirty_fields", Menu, menu.id))

    view |> element("#menu_form_form button", "Add entry") |> render_click()
    settle(view)

    assert_receive {:dirty_fields, fields, _user_id}, 1_000
    assert "menu[items]" in fields
  end
end
