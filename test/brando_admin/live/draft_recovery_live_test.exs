defmodule BrandoAdmin.DraftRecoveryLiveTest do
  # The recovery copy panel on the page form: the notice, the copy table,
  # discarding, a failed restore and starting fresh. These were browser tests
  # in e2e/playwright/tests/pages/drafts.spec.js. The panel is
  # server-rendered; copies are made here the way the form's hook makes them,
  # by sending `draft_capture`. Capturing as you type, clipboard, downloads,
  # reload recovery and module changes stay in that spec.
  use Brando.LiveCase

  alias Brando.Drafts
  alias Brando.Pages.Page

  @create "/admin/pages/create"

  defp identity(user, entry_id \\ nil), do: Drafts.identity(Page, entry_id, user.id)

  # The form component; the hook pushes its events there.
  defp form_cid(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[data-phx-component]")
    |> Enum.filter(&(Floki.find(&1, "#page_form-el") != []))
    |> Enum.min_by(&(&1 |> Floki.raw_html() |> byte_size()))
    |> Floki.attribute("data-phx-component")
    |> hd()
    |> String.to_integer()
  end

  defp form_event(view, event, params), do: view |> with_target(form_cid(view)) |> render_click(event, params)

  # Types into the main fields, then captures as the hook does.
  defp capture(view, fields) do
    view |> form("#page_form_form", %{"page" => fields}) |> render_change()
    main = view |> render() |> form_params("#page_form_form") |> Plug.Conn.Query.encode()

    view
    |> with_target(form_cid(view))
    |> render_hook("draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 1, "request_id" => 1})

    assert_status(view, "Recovery copy saved at")
  end

  defp assert_status(view, text) do
    assert view |> element("[data-testid=draft-status]") |> render() =~ text
  end

  defp mount(conn, path \\ @create) do
    {view, _html} = live_form(conn, path)
    view
  end

  defp open_panel(view) do
    view |> element(".draft-save-history") |> render_click()
    assert has_element?(view, "[data-testid=draft-panel]")
  end

  defp rows(view), do: view |> render() |> Floki.parse_document!() |> Floki.find(".draft-copy-table tbody tr")

  defp times(view),
    do: view |> render() |> Floki.parse_document!() |> Floki.find(".draft-copy-table time") |> Floki.attribute("datetime")

  defp select_copy(view, title) do
    view |> element("[data-testid=draft-panel] .draft-copy-table button", title) |> render_click()
  end

  defp title_value(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find("#page_title") |> Floki.attribute("value")
  end

  test "identical copies are one choice, and discarding it leaves nothing to recover", %{conn: conn, current_user: user} do
    view = mount(conn)
    capture(view, %{"title" => "Autumn campaign", "uri" => "autumn-campaign"})

    # Three more copies with the same content, from other sessions
    [copy] = Drafts.list(identity(user))

    for _ <- 1..3 do
      {:ok, _} =
        Drafts.write(identity(user), Ecto.UUID.generate(), 1, copy.payload, copy.base_fingerprint, copy.schema_version)
    end

    view = mount(conn)
    assert has_element?(view, "[data-testid=draft-notice]")
    assert title_value(view) in [[], [""]]
    view |> element("[data-testid=draft-notice] button[phx-click=draft_open]") |> render_click()
    assert length(rows(view)) == 1

    view |> element("[data-testid=draft-panel] button[phx-click=draft_discard]") |> render_click()
    refute has_element?(view, "[data-testid=draft-panel]")

    view = mount(conn)
    refute has_element?(view, "[data-testid=draft-notice]")
    refute has_element?(view, ".draft-save-history")
  end

  test "closing and reopening the copies keeps their capture times and order", %{conn: conn, current_user: user} do
    view = mount(conn)
    capture(view, %{"title" => "Autumn campaign", "uri" => "autumn-campaign"})
    [copy] = Drafts.list(identity(user))

    for index <- 1..10 do
      payload = put_in(copy.payload, ["main", "title"], "Autumn campaign #{index}")

      {:ok, older} =
        Drafts.write(identity(user), Ecto.UUID.generate(), 1, payload, copy.base_fingerprint, copy.schema_version)

      older |> Ecto.Changeset.change(updated_at: DateTime.add(copy.updated_at, -index * 60, :second)) |> Repo.update!()
    end

    view = mount(conn)
    open_panel(view)
    before = times(view)
    assert length(Enum.uniq(before)) == 11

    view |> element("[data-testid=draft-panel] button[phx-click=draft_dismiss]") |> render_click()
    open_panel(view)
    assert times(view) == before

    view = mount(conn)
    open_panel(view)
    assert times(view) == before
  end

  test "a failed restore is remembered, and starting fresh leaves both copies to choose from",
       %{conn: conn, current_user: user} do
    view = mount(conn)
    capture(view, %{"title" => "Autumn campaign", "uri" => "autumn-campaign"})
    [copy] = Drafts.list(identity(user))
    copy |> Ecto.Changeset.change(format_version: 999) |> Repo.update!()

    view = mount(conn)
    open_panel(view)
    select_copy(view, "Autumn campaign")
    form_event(view, "draft_restore", %{"id" => copy.id})
    assert view |> element("[data-testid=draft-panel] [role=alert]") |> render() =~ "unsupported format"
    refute has_element?(view, "button[phx-click=draft_restore_compatible]")

    # Tried once, it does not ask again
    view = mount(conn)
    refute has_element?(view, "[data-testid=draft-panel]")
    refute has_element?(view, "[data-testid=draft-notice]")

    open_panel(view)
    # Starting fresh opens a blank form
    view |> element("[data-testid=draft-panel] button[phx-click=draft_clean]", "Start fresh") |> render_click()
    assert_redirect(view, @create)
    view = mount(conn)
    assert title_value(view) in [[], [""]]
    refute has_element?(view, ".entry-block")
    refute has_element?(view, "[data-testid=draft-notice]")

    capture(view, %{"title" => "A fresh start"})
    view = mount(conn)
    open_panel(view)
    assert has_element?(view, "[data-testid=draft-panel] button", "Autumn campaign")
    assert has_element?(view, "[data-testid=draft-panel] button", "A fresh start")
  end
end
