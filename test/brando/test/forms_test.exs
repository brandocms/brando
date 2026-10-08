defmodule Brando.Test.FormsTest do
  use Brando.LiveCase
  use Brando.Test

  alias Brando.Pages.Page
  alias Brando.SyncTest.Article

  test "edits and saves an entry", %{conn: conn, current_user: user} do
    article = insert_entry(Article, %{title: "Before"}, user: user)
    {view, html} = open_form(conn, article)
    assert html =~ "Before"

    assert fill_form(view, Article, title: "After") =~ "After"
    assert {:ok, "/admin/articles" <> _} = save_form(view, Article)
    assert Brando.Repo.get!(Article, article.id).title == "After"
  end

  # The failed save is logged.
  @tag :capture_log
  test "returns the validation errors the form shows", %{conn: conn, current_user: user} do
    article = insert_entry(Article, %{title: "Kept"}, user: user)
    {view, _html} = open_form(conn, article)

    assert {:error, %{title: [_ | _]}} = save_form(view, Article, title: "")
    assert %{title: [_ | _]} = form_errors(view, Article)
    assert Brando.Repo.get!(Article, article.id).title == "Kept"
  end

  test "creates an entry from the create form", %{conn: conn} do
    {view, _html} = open_form(conn, Page)

    assert {:ok, _path} = save_form(view, Page, title: "Created in the form", uri: "created-in-the-form")
    assert Brando.Repo.get_by!(Page, uri: "created-in-the-form").title == "Created in the form"
  end

  test "adds a block and saves it with the entry", %{conn: conn, current_user: user} do
    module =
      Brando.ProposalFixtures.module!(user, "Text", "<p>{{ heading }}</p>",
        vars: [%{type: "string", key: "heading", label: "Heading", value: "From the form"}]
      )

    page = insert_entry(Page, %{title: "Blocks"}, user: user)
    {view, _html} = open_form(conn, page)

    uid = add_block(view, Page, module)
    assert render(view) =~ ~s(data-block-uid="#{uid}")
    assert {:ok, _path} = save_form(view, Page)

    assert Brando.Repo.get!(Page, page.id).rendered_blocks =~ "<p>From the form</p>"
  end

  test "names a field the blueprint does not have", %{conn: conn, current_user: user} do
    {view, _html} = open_form(conn, insert_entry(Article, %{}, user: user))
    assert_raise ArgumentError, ~r/has no field :headline/, fn -> fill_form(view, Article, headline: "x") end
  end
end
