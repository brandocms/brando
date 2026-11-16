defmodule Brando.Tenant.ServedHosts.SystemResolverTest do
  use ExUnit.Case, async: true

  alias Brando.Tenant.ServedHosts.SystemResolver

  # `localhost` resolves through `/etc/hosts`, with no name server to ask
  test "looks a host up through the operating system" do
    assert {:ok, addresses} = SystemResolver.lookup("localhost")
    assert {127, 0, 0, 1} in addresses
  end
end
