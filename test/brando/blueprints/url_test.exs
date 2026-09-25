defmodule Brando.Blueprint.URLTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.URL

  defmodule Entry do
    defstruct [:path]

    def __absolute_url__(entry), do: entry.path
  end

  test "resolves the generated Blueprint URL function" do
    assert URL.resolve(%Entry{path: "/projects/example"}) == "/projects/example"
    assert URL.resolve(nil) == ""
  end

  test "passes the entry to the generated function when adding the host" do
    endpoint = Brando.RuntimeConfig.web_module(Endpoint)

    assert URL.resolve(%Entry{path: "/projects/example"}, :with_host) ==
             Path.join("#{endpoint.url()}", "/projects/example")
  end

  # The bare host would read as a link to the front page.
  test "an entry without a URL gives nil with the host, not the front page" do
    assert URL.resolve(%Entry{path: nil}, :with_host) == nil
    assert URL.resolve(%Entry{path: ""}, :with_host) == nil
    assert URL.resolve(%Brando.Pages.Page{language: "en", uri: "404", has_url: false}, :with_host) == nil
  end

  test "has_url?/1 asks the Blueprint" do
    assert URL.has_url?(%Brando.Pages.Page{has_url: true})
    refute URL.has_url?(%Brando.Pages.Page{has_url: false})
    refute URL.has_url?(%Entry{path: "/x"})
    refute URL.has_url?(nil)
  end
end
