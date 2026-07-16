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
end
