defmodule BrandoAdmin.GlobalsLiveTest do
  # Setting up a global set with variables of several types, and filling in
  # its values on the Globals screen. These were browser tests
  # (e2e/playwright/tests/configuration/globals.spec.js and
  # e2e/playwright/tests/pages/globals.spec.js). The global set form, its
  # option pickers and the Globals screen are all server-rendered.
  use Brando.LiveCase

  setup do
    # Saving a set refreshes the global globals cache. Put back what it held,
    # since the database rows behind the new value are rolled back.
    cached = Brando.Cache.get(:globals)
    on_exit(fn -> Brando.Cache.put(:globals, cached, :infinite) end)
    :ok
  end

  defp new_set(conn, label, key) do
    {:ok, list, _html} = live(conn, "/admin/config/global_sets")
    render_async(list)
    assert has_element?(list, "a[href='/admin/config/global_sets/create']", "Create new")

    {view, _html} = live_form(conn, "/admin/config/global_sets/create", "global_set_form")
    view |> form("#global_set_form_form", %{"global_set" => %{"label" => label, "key" => key}}) |> render_change()
    assert view |> element("#global_set_label") |> render() =~ ~s(value="#{label}")
    view
  end

  # Opens a variable's option picker ("Select") and clicks an option.
  defp pick(view, index, field, option) do
    view |> element("#global_set_vars_#{index}_#{field}-field-base button", "Select") |> render_click()
    view |> element("#select-global_set_vars_#{index}-select-#{field}-modal button", option) |> render_click()
  end

  defp add_var(view, index, var) do
    view |> element("#global_set_form_form button", "Add entry") |> render_click()
    assert has_element?(view, "#global_set_vars_#{index}-edit")

    if var[:type], do: pick(view, index, "type", var.type)
    pick(view, index, "width", ~r/^\s*Half/)

    fields =
      Map.merge(
        %{"key" => var.key, "label" => %{"en" => var.label}},
        Map.take(var, [:instructions, :placeholder]) |> Map.new(fn {k, v} -> {to_string(k), v} end)
      )

    view
    |> form("#global_set_form_form", %{"global_set" => %{"vars" => %{"#{index}" => fields}}})
    |> render_change()
  end

  defp save(view) do
    view |> form("#global_set_form_form") |> render_submit()
    assert_redirect(view, "/admin/config/global_sets", 3_000)
  end

  defp attribute(html, name), do: html |> Floki.parse_fragment!() |> Floki.attribute(name)

  # The id of the control whose label reads `text`, inside `scope`.
  defp labelled(view, scope, text) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(scope <> " label")
    |> Enum.filter(&(&1 |> Floki.text() |> String.trim() == text))
    |> Enum.flat_map(&Floki.attribute(&1, "for"))
    |> then(fn [id] -> id end)
  end

  defp saved_set(key), do: Repo.get_by!(Brando.Sites.GlobalSet, key: key) |> Repo.preload(:vars)

  test "a global set is saved with a string, a boolean and a colour variable", %{conn: conn} do
    view = new_set(conn, "Configuration", "config")

    add_var(view, 0, %{
      key: "reservation",
      label: "Reservation Link",
      instructions: "URL to booking agent",
      placeholder: "https://url.here.com"
    })

    add_var(view, 1, %{key: "boolean", label: "Boolean value", type: "Boolean", instructions: "Instructions for boolean"})
    add_var(view, 2, %{key: "color", label: "Color value", type: "Color", instructions: "Instructions for color"})
    save(view)

    {:ok, list, _html} = live(conn, "/admin/config/global_sets")
    render_async(list)

    assert list
           |> render()
           |> Floki.parse_document!()
           |> Floki.find("*")
           |> Enum.count(&(Floki.text(&1, deep: false) |> String.trim() == "3 variables")) == 1

    set = saved_set("config")

    assert [
             %{
               key: "reservation",
               type: :string,
               width: :half,
               instructions: "URL to booking agent",
               placeholder: "https://url.here.com"
             },
             %{key: "boolean", type: :boolean, width: :half, instructions: "Instructions for boolean"},
             %{key: "color", type: :color, width: :half, instructions: "Instructions for color"}
           ] = Enum.sort_by(set.vars, & &1.sequence)

    assert Enum.map(Enum.sort_by(set.vars, & &1.sequence), & &1.label["en"]) ==
             ["Reservation Link", "Boolean value", "Color value"]
  end

  test "a global's value is saved on the Globals screen and shown again", %{conn: conn, current_user: user} do
    view = new_set(conn, "Coverage globals", "coverage")
    add_var(view, 0, %{key: "announcement", label: "Announcement"})
    save(view)

    {:ok, globals, _html} = live(conn, "/admin/globals")
    render_async(globals)
    assert has_element?(globals, "h1", "Globals")
    assert has_element?(globals, ".global-set-tabs button", "Coverage globals")

    # The set's tab names its panel; its form has no id of its own.
    [panel] = globals |> element(".global-set-tabs button", "Coverage globals") |> render() |> attribute("aria-controls")
    form_selector = "##{panel} form"
    input_id = labelled(globals, "##{panel}", "Announcement")
    [name] = globals |> element("[id='#{input_id}']") |> render() |> attribute("name")

    params = Plug.Conn.Query.decode(URI.encode_query([{name, "Site maintenance at midnight"}]))
    Brando.endpoint().subscribe("user:#{user.id}")
    globals |> form(form_selector, params) |> render_submit()
    # The toast goes to the user's channel, which the admin shows it from.
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Global set updated"}}

    {:ok, globals, _html} = live(conn, "/admin/globals")
    render_async(globals)
    assert globals |> element("[id='#{input_id}']") |> render() =~ ~s(value="Site maintenance at midnight")
  end
end
