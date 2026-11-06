defmodule BrandoAdmin.RevisionRefusedKeyTest do
  # A revision taken while a fragment's key didn't fit the key format can't
  # bring that key back once the fragment is renamed. The revisions drawer
  # says which field refused it, and Activity shows a scheduled one that was
  # cancelled for it.
  use Brando.LiveCase, async: true

  alias Brando.Pages
  alias Brando.Pages.Fragment

  setup %{current_user: user} do
    fragment = Factory.insert(:fragment, title: "Footer", wrapper: nil, key: "Stored&key")
    {:ok, _} = Brando.Revisions.create_revision(fragment, user)
    [%{revision: old}] = Repo.all(Brando.Revisions.Revision)

    {:ok, changed} = Pages.update_fragment(fragment.id, %{key: "footer"}, user)
    {:ok, _} = Brando.Revisions.create_revision(changed, user)

    %{fragment: changed, old: old}
  end

  defp drawer(c) do
    {view, _html} = live_form(c.conn, "/admin/pages/fragments/update/#{c.fragment.id}", "fragment_form")
    {view, view |> cid_of("#fragment_form-revisions-drawer-tab-activity") |> then(&with_target(view, &1))}
  end

  test "activating it names the field and why", c do
    {view, drawer} = drawer(c)

    drawer |> render_hook("activate_revision", %{"value" => to_string(c.old)})

    assert_push_event(view, "b:alert", %{type: "error", message: message})
    assert message =~ "Key: can only hold letters, digits, spaces and _ - . / ( )"
    assert Repo.get!(Fragment, c.fragment.id).key == "footer"
  end

  test "a scheduled one cancelled for it shows in the drawer's activity", c do
    Brando.Revisions.mark_revision_scheduled(Fragment, c.fragment.id, c.old, true)

    job = %Oban.Job{
      attempt: 1,
      max_attempts: 10,
      args: %{"schema" => to_string(Fragment), "id" => c.fragment.id, "revision" => c.old, "user_id" => c.current_user.id}
    }

    assert {:cancel, :invalid} = Brando.Worker.EntryPublisher.perform(job)

    {view, _drawer} = drawer(c)
    view |> element(~s(button[aria-controls="fragment_form-revisions-drawer"])) |> render_click()
    html = view |> element("#fragment_form-revisions-drawer") |> render()

    assert html =~ "##{c.old}"
    assert html =~ "Not valid: key"
  end

  # A revision whose var lost its required label: the page itself validates
  test "activating one that no longer validates in a nested record names it", c do
    {page, revision} = Brando.InvalidRevisions.page_with_invalid_var!(c.current_user)
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{page.id}", "page_form")
    drawer = view |> cid_of("#page_form-revisions-drawer-tab-activity") |> then(&with_target(view, &1))

    drawer |> render_hook("activate_revision", %{"value" => to_string(revision)})

    assert_push_event(view, "b:alert", %{type: "error", message: message})
    assert message =~ "Page variables → Label: can't be blank"
    assert Repo.get!(Brando.Pages.Page, page.id).title == "Changed since"
  end
end
