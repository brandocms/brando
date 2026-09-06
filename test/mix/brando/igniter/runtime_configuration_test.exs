defmodule Mix.Brando.Igniter.RuntimeConfigurationTest do
  use ExUnit.Case, async: false

  test "runtime entry points respect explicit endpoint and router selection" do
    keys = [:endpoint_module, :router_module]
    previous = Enum.map(keys, &{&1, Application.fetch_env(:brando, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:brando, key, value)
        {key, :error} -> Application.delete_env(:brando, key)
      end)
    end)

    Application.put_env(:brando, :endpoint_module, CustomWeb.APIEndpoint)
    Application.put_env(:brando, :router_module, CustomWeb.AdminRouter)
    assert Brando.endpoint() == CustomWeb.APIEndpoint
    assert Brando.router() == CustomWeb.AdminRouter
    assert Brando.helpers() == CustomWeb.AdminRouter.Helpers
    assert Brando.routes() == CustomWeb.AdminRouter.Helpers
  end
end
