defmodule BrandoAdmin.RevisionInvalidColorsTest do
  # A revision taken before colour values were checked may hold a colour
  # that is not one. Activating it, or loading it as a working copy, leaves
  # that colour empty and says so, rather than refusing.
  use Brando.LiveCase

  alias Brando.Pages.Page

  setup %{current_user: user} do
    {:ok, page} =
      Brando.Pages.create_page(
        Factory.params_for(:page,
          uri: "colours",
          # Without a publishing date: a working copy's datetime input cannot
          # show one taken from a revision yet (a revision's dates come back
          # as maps), which is not what these tests are about.
          status: :draft,
          publish_at: nil,
          vars: [%{type: :color, key: "bg", label: %{"en" => "Bg"}, value: "#000000"}]
        ),
        user
      )

    page = Repo.preload(page, Brando.Blueprint.preloads_for(Page))
    [var] = page.vars
    stored = %{page | title: "Older", vars: [%{var | value: "red;background:url(x)"}]}
    {:ok, revision} = Brando.Revisions.create_revision(stored, user, false)

    %{page: page, revision: revision}
  end

  defp drawer(c) do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    {view, view |> cid_of("#page_form-revisions-drawer-tab-activity") |> then(&with_target(view, &1))}
  end

  test "activating the revision restores the colour empty, with a warning", c do
    {view, drawer} = drawer(c)

    drawer |> render_hook("activate_revision", %{"value" => to_string(c.revision.revision)})

    assert_push_event(view, "b:alert", %{type: "warning"})
    restored = Page |> Repo.get!(c.page.id) |> Repo.preload(:vars)
    assert {restored.title, Enum.map(restored.vars, & &1.value)} == {"Older", [nil]}
  end

  test "loading it as a working copy warns too", c do
    {view, drawer} = drawer(c)

    drawer |> render_hook("select_revision", %{"revision" => to_string(c.revision.revision)})

    assert_push_event(view, "b:alert", %{type: "warning"})
  end

  test "a revision with valid colours activates without a warning", c do
    {:ok, revision} = Brando.Revisions.create_revision(%{c.page | title: "Valid"}, c.current_user, false)
    {view, drawer} = drawer(c)

    drawer |> render_hook("activate_revision", %{"value" => to_string(revision.revision)})

    refute_push_event(view, "b:alert", %{type: "warning"})
    assert Repo.get!(Page, c.page.id).title == "Valid"
  end
end
