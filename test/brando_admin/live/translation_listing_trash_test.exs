defmodule BrandoAdmin.TranslationListingTrashTest do
  # A synchronized translation in the trash, as the listing shows it: not a
  # language version, and creating its language again is refused (#3752).
  # Not async: pages are made synchronized through the application env.
  use Brando.LiveCase, async: false

  import ExUnit.CaptureLog

  alias Brando.Pages.Page
  alias Brando.Translations

  setup %{current_user: user} do
    put_test_env(Page, translatable: [mode: :synchronized])
    # The listing shows the content language, English
    source = Factory.insert(:page, title: "About", uri: "about", language: :en, creator: user)
    {:ok, target} = Translations.create_target(Page, source.id, :no, user)
    {:ok, _} = Brando.Pages.delete_page(target.id, user)
    %{source: source, target: target}
  end

  test "leaves a version in the trash out, and refuses to create its language again", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, "/admin/pages")
    await_selector(view, ".listing-translations")

    assert has_element?(view, "a.listing-translation.is-source[href='/admin/pages/update/#{c.source.id}']")
    refute has_element?(view, "a.listing-translation[href='/admin/pages/update/#{c.target.id}']")

    log =
      capture_log(fn ->
        view |> element("[id$='_create_translation_#{c.source.id}_lang_no']") |> render_click()
      end)

    assert log =~ ":language_in_trash"
    # The version in the trash keeps its place, and no other was created
    %{group_id: group_id} = Translations.get_member(Page, c.source.id)
    assert [c.source.id, c.target.id] == Enum.map(Translations.list_members(group_id), & &1.entry_id)
  end
end
