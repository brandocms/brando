defmodule BrandoAdmin.TranslationListingTrashTest do
  # A synchronized translation in the trash, as the listing shows it: not a
  # language version, and creating its language again without the dialog's
  # confirmation is refused (#3752). The confirmed replace is in
  # `BrandoAdmin.TranslationReplaceTrashedTest` (#3762).
  # Not async: pages are made synchronized through the application env.
  use Brando.LiveCase, async: false

  import ExUnit.CaptureLog

  alias Brando.Pages.Page
  alias Brando.Translations
  alias BrandoIntegration.Repo

  setup %{current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    # The listing shows the content language, English
    source = Factory.insert(:page, title: "About", uri: "about", language: :en, creator: user)
    {:ok, target} = Translations.create_target(Page, source.id, :no, user)
    {:ok, _} = Brando.Pages.delete_page(target.id, user)
    %{source: source, target: target}
  end

  test "leaves a version in the trash out, and refuses to create its language again unconfirmed", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, "/admin/pages")
    await_selector(view, ".listing-translations")

    assert has_element?(view, "a.listing-translation.is-source[href='/admin/pages/update/#{c.source.id}']")
    refute has_element?(view, "a.listing-translation[href='/admin/pages/update/#{c.target.id}']")

    log =
      capture_log(fn ->
        # The event the row's button sends for a free language, as a listing
        # that has not caught up with the trash would send it
        render_click(view, "create_entry_translation", %{"id" => to_string(c.source.id), "language" => "no"})
      end)

    # An expected refusal, told to the editor and not logged as an error
    refute log =~ ":language_in_trash"
    # The version in the trash keeps its place, and no other was created
    %{group_id: group_id} = Translations.get_member(Page, c.source.id)
    assert [c.source.id, c.target.id] == Enum.map(Translations.list_members(group_id), & &1.entry_id)
  end

  # The listing's toast, from the user's channel
  defp delete_toast(view, id) do
    render_click(view, "delete_entry", %{"id" => to_string(id)})
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}}
    message
  end

  test "refusing to delete the source says when a translation in the trash counts", %{conn: conn} = c do
    Brando.endpoint().subscribe("user:#{c.current_user.id}")
    {:ok, view, _html} = live(conn, "/admin/pages")

    in_trash = delete_toast(view, c.source.id)
    {:ok, _} = Brando.Authorization.Boundary.restore(c.current_user, Repo.get!(Page, c.target.id))
    synchronized = delete_toast(view, c.source.id)

    refute Repo.get!(Page, c.source.id).deleted_at
    assert in_trash != synchronized
  end
end
