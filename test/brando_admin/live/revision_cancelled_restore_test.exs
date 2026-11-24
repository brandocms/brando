defmodule BrandoAdmin.RevisionCancelledRestoreTest do
  # Postgres cancels one of two transactions that wait for each other. When
  # it is a revision restore (against a release apply moving values in the
  # same blocks, `Brando.Content.DefinitionRenamesConcurrencyTest`), the
  # drawer says so and activating it again restores it.
  use Brando.LiveCase

  alias Brando.Pages.Page

  setup %{current_user: user} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)

    page = Factory.insert(:page, title: "Before")
    {:ok, _} = Brando.Revisions.create_revision(page, user)
    [%{revision: old}] = Repo.all(Brando.Revisions.Revision)

    {:ok, changed} = Brando.Pages.update_page(page.id, %{title: "After"}, user)
    %{page: changed, old: old}
  end

  # The pages table cancels each update as Postgres cancels a deadlock's
  # victim, until the trigger is dropped
  defp cancel_updates! do
    Repo.query!("""
    CREATE FUNCTION cancel_restore() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'deadlock detected' USING ERRCODE = '40P01'; END $$ LANGUAGE plpgsql
    """)

    Repo.query!("CREATE TRIGGER cancel_restore BEFORE UPDATE ON pages FOR EACH ROW EXECUTE FUNCTION cancel_restore()")
  end

  test "a restore Postgres cancels keeps the drawer, says so, and activating again restores it", c do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}", "page_form")
    drawer = view |> cid_of("#page_form-revisions-drawer-tab-activity") |> then(&with_target(view, &1))
    cancel_updates!()

    drawer |> render_hook("activate_revision", %{"value" => to_string(c.old)})

    assert_push_event(view, "b:alert", %{type: "error"})
    assert Process.alive?(view.pid)
    assert Repo.get!(Page, c.page.id).title == "After"

    Repo.query!("DROP TRIGGER cancel_restore ON pages")
    drawer |> render_hook("activate_revision", %{"value" => to_string(c.old)})

    assert Repo.get!(Page, c.page.id).title == "Before"
  end
end
