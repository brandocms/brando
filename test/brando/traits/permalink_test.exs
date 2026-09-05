defmodule Brando.Trait.PermalinkTest do
  use ExUnit.Case, async: true

  alias Brando.Trait.Permalink

  defmodule Entry do
    defstruct [:id, :url, :language, has_url: true]
    def has_trait(Brando.Trait.Permalink), do: true
    def __absolute_url__(entry), do: entry.url
    def __absolute_url_preloads__, do: []
  end

  defmodule WithoutTrait do
    defstruct [:id, :url]
    def has_trait(_), do: false
    def __absolute_url__(_), do: raise("must not render URLs for schemas without the trait")
  end

  test "the built-in atom registers the runtime-only trait" do
    assert Brando.Pages.Page.has_trait(Permalink)
    assert Brando.Pages.Page.__trait__(Permalink) == []
  end

  test "compares the saved URL and uses the previous language" do
    previous = %Entry{id: 1, url: "/en/old", language: :en}
    saved = %{previous | url: "/no/new", language: :no}

    assert Permalink.redirect_for(previous, saved, "no") ==
             %{from: "/en/old", to: "/no/new", code: 301, language: "en"}
  end

  test "supports full URLs and a default language" do
    previous = %Entry{id: 1, url: "https://example.com/old"}
    saved = %{previous | url: "https://example.com/new"}

    assert Permalink.redirect_for(previous, saved, "en") ==
             %{from: "/old", to: "https://example.com/new", code: 301, language: "en"}
  end

  test "ignores new entries, unchanged URLs and disabled URLs" do
    previous = %Entry{id: 1, url: "/old"}
    saved = %{previous | url: "/new"}
    refute Permalink.redirect_for(%{previous | id: nil}, saved, "en")
    refute Permalink.redirect_for(nil, saved, "en")
    refute Permalink.redirect_for(previous, previous, "en")
    refute Permalink.redirect_for(%{previous | has_url: false}, saved, "en")
    refute Permalink.redirect_for(previous, %{saved | has_url: false}, "en")
  end

  test "ignores missing, non-web and query-only URLs that cannot be matched by the redirect service" do
    entry = %Entry{id: 1, url: "/old"}

    for url <- [nil, "", " ", "relative", "#section", "mailto:test@example.com", "//example.com/new", "/old?q=1"] do
      refute Permalink.redirect_for(%{entry | url: url}, entry, "en")
      refute Permalink.redirect_for(entry, %{entry | url: url}, "en")
    end

    refute Permalink.redirect_for(entry, %{entry | url: "https://example.com/old"}, "en")
  end

  test "does not inspect schemas that have not opted in" do
    previous = %WithoutTrait{id: 1, url: "/old"}
    refute Permalink.redirect_for(previous, %{previous | url: "/new"}, "en")
  end
end
