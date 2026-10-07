defmodule BrandoAdmin.ContentConfigurationLiveTest do
  # Creating each kind of content configuration through its admin form, and
  # finding it in its listing afterwards. These were browser tests
  # (e2e/playwright/tests/configuration/content-configuration.spec.js), but
  # nothing in them needs a browser: the forms are server-rendered, and the
  # container's CodeMirror editor only mirrors its text into the `code`
  # textarea, which the form below fills in directly.
  use Brando.LiveCase

  @base "/admin/config/content"

  # `form_id` is the form component's id. A form without a block field saves
  # on the first submit. One with blocks first asks the client for their state
  # (`b:submit`) and saves on the submit that follows.
  defp create(conn, kind, form_id, params, opts \\ []) do
    {view, _html} = live_form(conn, "#{@base}/#{kind}/create", form_id)
    # `form/3` fails if a value names an input the form does not render.
    view |> form("##{form_id}_form", params) |> render_submit()

    if opts[:blocks?] do
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("##{form_id}_form", params) |> render_submit()
    end

    listing(view, conn, kind)
  end

  defp listing(view, conn, kind) do
    assert_redirect(view, "#{@base}/#{kind}", 3_000)
    {:ok, list, _html} = live(conn, "#{@base}/#{kind}")
    render_async(list)
    list
  end

  test "a module set is saved and listed with its module count", %{conn: conn} do
    list = create(conn, "module_sets", "module_set_form", %{"module_set" => %{"title" => "Editorial modules"}})

    assert has_element?(list, "a", "Editorial modules")
    assert render(list) =~ "0 modules in this set"
  end

  test "a container is saved with its code and listed under its namespace", %{conn: conn} do
    code = ~s(<section class="centered">{{ content }}</section>)

    list =
      create(conn, "containers", "container_form", %{
        "container" => %{"name" => "Centered content", "namespace" => "layout", "code" => code}
      })

    assert has_element?(list, "a", "Centered content")
    assert render(list) =~ "layout"
    assert [%{name: "Centered content", code: ^code}] = Brando.Repo.all(Brando.Content.Container)
  end

  test "a table template is saved and listed", %{conn: conn} do
    list = create(conn, "table_templates", "table_template_form", %{"table_template" => %{"name" => "Contact table"}})

    assert has_element?(list, "a", "Contact table")
  end

  test "a content template is saved and listed with its instructions", %{conn: conn} do
    params = %{
      "template" => %{
        "name" => "Landing page",
        "namespace" => "pages",
        "instructions" => "Start with a strong introduction"
      }
    }

    list = create(conn, "templates", "template_form", params, blocks?: true)

    assert has_element?(list, "a", "Landing page")
    assert render(list) =~ "Start with a strong introduction"
  end

  test "a palette is saved with a colour added in the form", %{conn: conn} do
    {view, _html} = live_form(conn, "#{@base}/palettes/create", "palette_form")

    view |> element("#palette_form_form button", "Add entry") |> render_click()
    assert has_element?(view, "#palette_colors_0_name")

    # The colour picker's hook writes the hidden hex input, so it arrives with
    # the submit rather than as a field `form/3` can fill.
    view
    |> form("#palette_form_form", %{
      "palette" => %{
        "status" => "published",
        "name" => "Ocean",
        "key" => "ocean",
        "namespace" => "brand",
        "colors" => %{"0" => %{"name" => "Deep blue", "key" => "deep-blue"}}
      }
    })
    |> render_submit(%{"palette" => %{"colors" => %{"0" => %{"hex_value" => "#123456"}}}})

    list = listing(view, conn, "palettes")
    assert has_element?(list, "a", "Ocean")
    assert render(list) =~ "brand"

    assert [%{status: :published, colors: [%{name: "Deep blue", key: "deep-blue", hex_value: "#123456"}]}] =
             Brando.Repo.all(Brando.Content.Palette)
  end
end
