defmodule Brando.SEO.SuggestionsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.SEO.Audit.Row
  alias Brando.SEO.Suggestion
  alias Brando.SEO.Suggestions

  setup do
    user = Factory.insert(:random_user)
    Phoenix.PubSub.subscribe(Brando.pubsub(), Suggestions.topic())
    {:ok, user: user}
  end

  defp create_page(user, title, uri) do
    {:ok, page} =
      Pages.create_page(%{title: title, uri: uri, language: "en", template: "default.html", status: :published}, user)

    page
  end

  defp row(page), do: %Row{schema: Pages.Page, id: page.id, title: page.title}

  defp description(page) do
    {:ok, page} = Pages.get_page(%{matches: %{id: page.id}})
    page.meta_description
  end

  test "queued suggestions are written in the background, and the entry is left alone", %{user: user} do
    Brando.AIStub.configure()
    Brando.AIStub.reply(fn prompt -> if prompt =~ "Batch one", do: "About batch one", else: "About batch two" end)

    one = create_page(user, "Batch one", "batch-one")
    two = create_page(user, "Batch two", "batch-two")

    assert {:ok, 2} = Suggestions.enqueue([row(one), row(two)], "en", user)
    assert_received {:seo_suggestions_updated, "en"}

    suggestions = Suggestions.list_open("en")

    assert Enum.map(suggestions, &{&1.title, &1.status, &1.text}) == [
             {"Batch one", :pending, "About batch one"},
             {"Batch two", :pending, "About batch two"}
           ]

    assert Enum.all?(suggestions, &(&1.model == "openai:gpt-4o-mini" and &1.requested_by_id == user.id))
    assert description(one) == nil
    assert description(two) == nil
  end

  test "accepting writes the suggestion, or the editor's version of it", %{user: user} do
    Brando.AIStub.configure()
    Brando.AIStub.reply("Suggested text")

    one = create_page(user, "Accept one", "accept-one")
    two = create_page(user, "Accept two", "accept-two")
    {:ok, 2} = Suggestions.enqueue([row(one), row(two)], "en", user)
    [first, second] = Suggestions.list_open("en")

    assert {:ok, %Suggestion{status: :accepted, reviewed_by_id: reviewed_by}} =
             Suggestions.accept(first.id, nil, user)

    assert reviewed_by == user.id
    assert {:ok, %Suggestion{text: "Edited by hand"}} = Suggestions.accept(second.id, " Edited by hand ", user)

    assert description(one) == "Suggested text"
    assert description(two) == "Edited by hand"
    assert Suggestions.list_open("en") == []
    # Already accepted: nothing left to accept.
    assert Suggestions.accept(first.id, nil, user) == {:error, :not_found}
  end

  test "rejecting leaves the entry alone, and a later run asks again", %{user: user} do
    Brando.AIStub.configure()
    Brando.AIStub.reply("First try")

    page = create_page(user, "Reject me", "reject-me")
    {:ok, 1} = Suggestions.enqueue([row(page)], "en", user)
    [suggestion] = Suggestions.list_open("en")

    assert {:ok, %Suggestion{status: :rejected}} = Suggestions.reject(suggestion.id, user)
    assert description(page) == nil
    assert Suggestions.list_open("en") == []

    Brando.AIStub.reply("Second try")
    assert {:ok, 1} = Suggestions.enqueue([row(page)], "en", user)
    assert [%Suggestion{id: id, status: :pending, text: "Second try"}] = Suggestions.list_open("en")
    assert id == suggestion.id
  end

  test "entries already waiting are skipped, and a run is capped", %{user: user} do
    Brando.AIStub.configure()
    Brando.AIStub.reply("Text")

    previous = Application.get_env(:brando, Brando.SEO)
    Application.put_env(:brando, Brando.SEO, max_batch: 2)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Brando.SEO, previous),
        else: Application.delete_env(:brando, Brando.SEO)
    end)

    pages = for n <- 1..3, do: create_page(user, "Capped #{n}", "capped-#{n}")

    assert {:ok, 2} = Suggestions.enqueue(Enum.map(pages, &row/1), "en", user)
    # The first two wait for review, so only the third is left to ask for.
    assert {:ok, 1} = Suggestions.enqueue(Enum.map(pages, &row/1), "en", user)
    assert length(Suggestions.list_open("en")) == 3
  end

  test "accept_all writes every pending suggestion", %{user: user} do
    Brando.AIStub.configure()
    Brando.AIStub.reply("Bulk text")

    pages = for n <- 1..2, do: create_page(user, "Bulk #{n}", "bulk-#{n}")
    {:ok, 2} = Suggestions.enqueue(Enum.map(pages, &row/1), "en", user)

    assert Suggestions.accept_all("en", user) == {2, 0}
    assert Enum.all?(pages, &(description(&1) == "Bulk text"))
  end

  test "a job that cannot succeed fails its suggestion at once, with a reason", %{user: user} do
    # No provider configured.
    page = create_page(user, "No provider", "no-provider")

    {:ok, 1} = Suggestions.enqueue([row(page)], "en", user)
    assert_received {:seo_suggestions_updated, "en"}

    assert [%Suggestion{status: :failed, error: error}] = Suggestions.list_open("en")
    assert error =~ "AI"

    [suggestion] = Suggestions.list_open("en")
    assert {:ok, %Suggestion{status: :rejected}} = Suggestions.reject(suggestion.id, user)
  end
end
