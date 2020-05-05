defmodule Brando.BrandoTest do
  use ExUnit.Case, async: true

  test "router" do
    assert Brando.router() == Brando.Integration.Router
  end

  test "endpoint" do
    assert Brando.endpoint() == Brando.Integration.Endpoint
  end

  test "repo" do
    assert Brando.repo() == Brando.Integration.Repo
  end
end
