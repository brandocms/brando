defmodule Brando.BrandoTest do
  use ExUnit.Case, async: true

  test "router" do
    assert Brando.router() == RouterHelper.TestRouter
  end

  test "endpoint" do
    assert Brando.endpoint() == Brando.Integration.Endpoint
  end

  test "repo" do
    assert Brando.repo() == Brando.Integration.TestRepo
  end

  test "config" do
    assert Brando.config(:router) == RouterHelper.TestRouter
  end
end
