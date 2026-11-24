defmodule Brando.Content.Proposals.RenderSavedTest do
  # The assistant's preview of a saved entry (`Preview.render_saved/3`): the
  # page reads the entry as a saved one is read. `Brando.SyncTest.Article`'s
  # default preview target lists its related entries and its alternates.
  use Brando.ConnCase, async: true

  alias Brando.Content.Proposals.Preview
  alias Brando.Factory
  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncTest.Article

  setup do
    user = Factory.insert(:random_user)

    {:ok, article} =
      Brando.SyncTest.create_article(%{title: "Article", slug: "article", language: "en", status: "draft"}, user)

    %{user: user, article: article}
  end

  defp render!(c) do
    assert {:ok, key} = Preview.render_saved(Article, c.article.id, c.user)
    {:ok, html} = LivePreview.get_cache(key)
    html
  end

  test "renders a page that reads a relation", c do
    page = Factory.insert(:page, creator: c.user, title: "Related page")
    {:ok, identifier} = Brando.Content.create_identifier(Page, page)
    join = Article.__schema__(:association, :related_entries).related
    Repo.insert!(struct(join, parent_id: c.article.id, identifier_id: identifier.id, sequence: 0))

    assert render!(c) =~ "Related page"
  end

  test "renders a page that reads its alternates", c do
    {:ok, alternate} =
      Brando.SyncTest.create_article(%{title: "Artikkel", slug: "artikkel", language: "no", status: "draft"}, c.user)

    Article.Alternate.add(c.article.id, alternate.id)

    assert render!(c) =~ "Artikkel"
  end
end
