defmodule Brando.BrandoTest do
  use ExUnit.Case, async: true

  test "router", do: assert(Brando.router() == BrandoIntegrationWeb.Router)
  test "endpoint", do: assert(Brando.endpoint() == BrandoIntegrationWeb.Endpoint)
  test "repo", do: assert(Brando.repo() == BrandoIntegration.Repo)
  test "factory", do: assert(Brando.factory() == BrandoIntegration.Factory)
  test "authorization", do: assert(Brando.authorization() == BrandoIntegration.Authorization)
  test "presence", do: assert(Brando.presence() == BrandoIntegration.Presence)
end
