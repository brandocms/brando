defmodule BrandoAdmin.LiveView.Listing.DeleteDescriptionTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Repo
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.LiveView.Listing.DeleteDescription

  defp article(title, items) do
    Repo.insert!(%Article{
      title: title,
      slug: "slug-#{System.unique_integer([:positive])}",
      language: :en,
      status: :published,
      items: Enum.map(items, &%ArticleItem{label: &1})
    })
  end

  test "names the entry and what's deleted with it" do
    entry = article("Parthenon", ["One", "Two"])

    assert %{title: title, message: message, confirm: "Delete", cancel: "Cancel"} =
             DeleteDescription.describe(Article, entry)

    assert title == "Delete article?"
    assert message =~ "<strong>Parthenon</strong> will be deleted together with 2 article items"
    assert message =~ "can't be undone"
  end

  test "leaves out owned relations that are empty, and escapes the name" do
    entry = article("<b>Bold</b>", [])
    %{message: message} = DeleteDescription.describe(Article, entry)

    assert message =~ "<strong>&lt;b&gt;Bold&lt;/b&gt;</strong> will be deleted."
    refute message =~ "together"
  end

  test "a soft-deleted entry is moved to Deleted, where it can be restored" do
    page = Brando.Factory.insert(:page, title: "About")
    %{message: message} = DeleteDescription.describe(Brando.Pages.Page, page)

    assert message =~ "<strong>About</strong> is moved to the list's Deleted filter"
    assert message =~ "It can be restored from there."
    refute message =~ "can't be undone"
  end
end
