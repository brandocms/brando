defmodule Brando.BrandoTest do
  use ExUnit.Case, async: true

  test "router", do: assert(Brando.router() == Brando.Integration.Router)
  test "endpoint", do: assert(Brando.endpoint() == Brando.Integration.Endpoint)
  test "repo", do: assert(Brando.repo() == Brando.Integration.Repo)
  test "factory", do: assert(Brando.factory() == Brando.Integration.Factory)
  test "authorization", do: assert(Brando.authorization() == Brando.Integration.Authorization)
  test "presence", do: assert(Brando.presence() == Brando.Integration.Presence)
end
