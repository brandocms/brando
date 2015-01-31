defmodule Brando.BrandoTest do
  use ExUnit.Case, async: true
  test "get_router" do
    assert(Brando.get_router() == RouterHelper.TestRouter)
  end
end