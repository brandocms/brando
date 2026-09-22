defmodule Brando.SEO.RedirectSuggestionsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.SEO.Audit.Row
  alias Brando.SEO.RedirectSuggestions

  setup do
    Brando.Cache.SEO.set()
    :ok
  end

  defp row(title, url), do: %Row{schema: Brando.Pages.Page, id: 1, title: title, url: url}

  test "an exact slug match becomes an exact suggestion, sorted by hits" do
    rows = [row("About", "/en/about"), row("Team", "/en/team")]
    log = [%{url: "/old/team", hits: 3}, %{url: "/pages/about", hits: 10}]

    assert [about, team] = RedirectSuggestions.suggest(log, rows, "en")
    assert about.to == "/en/about" and about.confidence == :exact and about.hits == 10
    assert team.to == "/en/team" and team.confidence == :exact
  end

  test "a near miss on the slug is a close suggestion; a different slug is none" do
    rows = [row("Sommerro", "/projects/sommerro")]

    assert [%{confidence: :close, to: "/projects/sommerro"}] =
             RedirectSuggestions.suggest([%{url: "/projects/sommero", hits: 1}], rows, "en")

    assert RedirectSuggestions.suggest([%{url: "/projects/vinterbro", hits: 1}], rows, "en") == []
  end

  test "probes and asset paths are ignored" do
    rows = [row("Env", "/env")]
    log = [%{url: "/wp-login.php", hits: 50}, %{url: "/.env", hits: 20}, %{url: "/static/env.css", hits: 2}]
    assert RedirectSuggestions.suggest(log, rows, "en") == []
    assert RedirectSuggestions.noise?("/xmlrpc.php")
    refute RedirectSuggestions.noise?("/projects/sommerro")
  end

  test "a URL already covered by a redirect is left out" do
    {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})

    Brando.Sites.update_seo(
      seo,
      %{"redirects" => [%{"from" => "/old/team", "to" => "/en/team", "code" => "301"}]},
      :system
    )

    rows = [row("Team", "/en/team")]
    assert RedirectSuggestions.suggest([%{url: "/old/team", hits: 3}], rows, "en") == []
  end
end
