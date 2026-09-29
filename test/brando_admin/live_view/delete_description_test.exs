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

  test "an entry without a name is \"this entry\", not the schema's noun spliced in" do
    entry = article("", [])
    %{message: message} = DeleteDescription.describe(Article, entry)

    assert message =~ "This entry will be deleted."
  end

  test "a soft-deleted entry is moved to Deleted, where it can be restored" do
    page = Brando.Factory.insert(:page, title: "About")
    %{message: message} = DeleteDescription.describe(Brando.Pages.Page, page)

    assert message =~ "<strong>About</strong> is moved to the list's Deleted filter"
    assert message =~ "It can be restored from there."
    refute message =~ "can't be undone"
  end

  describe "media in use" do
    test "names where it is used, linked, and counts past the first few" do
      image = Brando.Factory.insert(:image)
      unused = Brando.Factory.insert(:image)

      for n <- 1..7, do: Brando.Factory.insert(:video, title: "Video #{n}", thumbnail_id: image.id)

      %{message: message} = DeleteDescription.describe(Brando.Images.Image, image)

      assert message =~ "It is used in 7 places:"
      assert message =~ ~r{<a href="[^"]+" target="_blank">Video 1</a>}
      assert message =~ "2 more"
      refute message =~ "Video 7"

      refute DeleteDescription.describe(Brando.Images.Image, unused).message =~ "It is used"
    end
  end
end
