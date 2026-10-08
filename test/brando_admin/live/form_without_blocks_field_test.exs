defmodule BrandoAdmin.FormWithoutBlocksFieldTest do
  # The test article's `:no_blocks` form leaves out the schema's `blocks`
  # relation. Saving used to wait forever for a block field that was never
  # mounted.
  use Brando.LiveCase

  alias Brando.SyncTest

  test "a form that omits the schema's blocks field still saves", %{conn: conn, current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "No blocks here", slug: "no-blocks-here", language: "en", status: "published", year: 2020},
        user
      )

    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/no-blocks", "article_form")
    refute has_element?(view, "[id^='article_form-blocks-']")

    view
    |> form("#article_form_form")
    |> render_submit(%{"article" => %{"title" => "Saved without blocks"}})

    assert_push_event(view, "b:submit", %{}, 2_000)

    view
    |> form("#article_form_form")
    |> render_submit(%{"article" => %{"title" => "Saved without blocks"}})

    assert_redirect(view, 3_000)

    {:ok, saved} = SyncTest.get_article(%{matches: %{id: article.id}})
    assert saved.title == "Saved without blocks"
  end
end
