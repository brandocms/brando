defmodule Brando.Trait.Meta.ContentModifiedTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.Value
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Trait.Meta.ContentModified

  doctest ContentModified

  @article """
  <h2>Opening hours</h2>
  <p>The gallery is open from Tuesday to Sunday, between eleven and five. Guided
  tours start every hour on the hour and last about forty minutes. Groups of more
  than ten people should book a tour in advance by phone or email.</p>
  <p>Entrance is free for children under twelve and for members of the society.</p>
  """

  @long_ago ~U[2020-01-01 00:00:00Z]

  describe "substantive_change?/2" do
    test "a typo fix is not" do
      refute ContentModified.substantive_change?(@article, String.replace(@article, "eleven", "elevne"))
    end

    test "reordering paragraphs is not" do
      [heading, first, second] = String.split(@article, "\n<p>")
      refute ContentModified.substantive_change?(@article, Enum.join([heading, second, first], "\n<p>"))
    end

    test "a markup-only change is not" do
      refute ContentModified.substantive_change?(@article, String.replace(@article, "<p>", "<p class=\"lead\">"))
    end

    test "a new paragraph is" do
      addition = "<p>From March the café on the ground floor serves lunch every weekday, with soup and bread.</p>"
      assert ContentModified.substantive_change?(@article, @article <> addition)
    end

    test "rewriting a sentence is" do
      rewritten =
        String.replace(
          @article,
          "Guided\ntours start every hour on the hour and last about forty minutes.",
          "Guided tours have been replaced by an audio guide you can borrow at the desk for free."
        )

      assert ContentModified.substantive_change?(@article, rewritten)
    end

    test "writing the first words of an empty entry is" do
      assert ContentModified.substantive_change?(nil, "Opening hours are posted at the entrance.")
    end
  end

  describe "stamping on save" do
    setup do
      user = Factory.insert(:random_user)

      {:ok, page} =
        Pages.create_page(
          %{
            title: "Opening hours and guided tours at the gallery",
            uri: "content-modified-#{System.unique_integer([:positive])}",
            language: "en",
            template: "default.html",
            status: :published
          },
          user
        )

      %{user: user, page: page}
    end

    test "a new entry is stamped when it is created", %{page: page} do
      assert %DateTime{} = page.content_modified_at
      assert Value.modified_at(page) == page.content_modified_at
    end

    test "a small edit leaves it alone, a substantive one moves it", %{user: user, page: page} do
      backdate(page)

      {:ok, typo} = Pages.update_page(page.id, %{title: "Opening hours and guided tours at the galery"}, user)
      assert typo.content_modified_at == @long_ago
      assert %DateTime{} = typo.edited_at

      {:ok, rewritten} =
        Pages.update_page(
          page.id,
          %{title: "The gallery is closed for renovation until the spring, when it reopens with a new collection"},
          user
        )

      assert DateTime.after?(rewritten.content_modified_at, @long_ago)
    end

    test "rendered block text counts once enough of it changes", %{user: user, page: page} do
      backdate(page)
      page = Brando.Repo.get!(Pages.Page, page.id)

      few_words =
        page
        |> Ecto.Changeset.change(rendered_blocks: "<p>Tours start every hour.</p>")
        |> then(&Pages.update_page(&1, user))

      assert {:ok, %{content_modified_at: @long_ago}} = few_words

      page = Brando.Repo.get!(Pages.Page, page.id)

      {:ok, rewritten} =
        page
        |> Ecto.Changeset.change(rendered_blocks: "<p>Tours start every hour.</p>" <> paragraph())
        |> then(&Pages.update_page(&1, user))

      assert DateTime.after?(rewritten.content_modified_at, @long_ago)
    end

    test "system saves never move it", %{page: page} do
      backdate(page)

      {:ok, updated} =
        Pages.update_page(page.id, %{title: "A completely different title written by an import job overnight"}, :system)

      assert updated.content_modified_at == @long_ago
    end
  end

  test "modified_at/1 falls back to edited_at and updated_at" do
    edited = ~U[2026-02-01 10:00:00Z]
    updated = ~N[2026-03-01 10:00:00]

    assert Value.modified_at(%{content_modified_at: nil, edited_at: edited, updated_at: updated}) == edited
    assert Value.modified_at(%{edited_at: nil, updated_at: updated}) == updated
  end

  defp backdate(page) do
    Brando.Repo.update_all(from(p in Pages.Page, where: p.id == ^page.id), set: [content_modified_at: @long_ago])
  end

  defp paragraph,
    do: "<p>From March the café on the ground floor serves lunch every weekday, with soup, bread and coffee.</p>"
end
