defmodule Brando.SEO.AnalyzeTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.SEO.Analyze

  test "the prompt carries the meta, the content and the language to answer in" do
    entry = %Pages.Page{
      title: "Om oss",
      language: "no",
      meta_description: "Vi lager nettsteder",
      rendered_blocks: "<p>Et lite byrå i Oslo</p>"
    }

    prompt = Analyze.prompt(Pages.Page, entry, "no")

    assert prompt =~ "Reply in Norsk."
    assert prompt =~ "Meta description: Vi lager nettsteder"
    assert prompt =~ "Meta title: (none"
    assert prompt =~ "Content: Et lite byrå i Oslo"
    assert prompt =~ "Do not suggest keyword density"
  end

  test "the searches a page is shown for are added to the prompt" do
    queries = [%{query: "web agency oslo", impressions: 320, clicks: 4, position: 7.25}]
    prompt = Analyze.prompt(Pages.Page, %Pages.Page{title: "Om oss", language: "no"}, "en", queries)

    assert prompt =~ "Google searches that showed this page"
    assert prompt =~ "- web agency oslo (320 impressions, 4 clicks, position 7.3)"
    refute Analyze.prompt(Pages.Page, %Pages.Page{title: "Om oss"}, "en") =~ "Google searches"
  end

  test "keeps at most three points, whatever the model marks them with" do
    assert Analyze.points("- One\n* Two\n\n1. Three\n• Four") == ["One", "Two", "Three"]
  end

  test "critiques a stored entry without writing to it" do
    Brando.AIStub.configure()
    Brando.AIStub.reply(fn prompt -> if prompt =~ "Critiqued page", do: "- Too vague", else: "- Wrong page" end)
    user = Factory.insert(:random_user)

    {:ok, page} =
      Pages.create_page(
        %{
          title: "Critiqued page",
          uri: "critiqued",
          language: "en",
          template: "default.html",
          status: :published,
          meta_description: "A page"
        },
        user
      )

    assert Analyze.critique(Pages.Page, page.id, language: "en") == {:ok, ["Too vague"]}
    {:ok, page} = Pages.get_page(%{matches: %{id: page.id}})
    assert page.meta_description == "A page"
  end
end
