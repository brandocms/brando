defmodule E2eProject.EndpointBindingTest do
  # The fixture routes in the e2e build sign in anyone who asks, with no
  # credential: the loopback listener is their only access control.
  use ExUnit.Case, async: true

  alias E2eProjectWeb.Endpoint
  alias E2eProjectWeb.Router

  @loopback {127, 0, 0, 1}

  # What Mix ends up with at boot: compile-time config, with runtime.exs merged
  # over it.
  defp booted_config(env) do
    env
    |> compile_config()
    |> Config.Reader.merge(Config.Reader.read!(config_path("runtime.exs"), env: env))
    |> get_in([:e2e_project])
  end

  defp compile_config(env), do: Config.Reader.read!(config_path("config.exs"), env: env)

  defp config_path(file), do: Path.expand("../../config/#{file}", __DIR__)

  for env <- [:test, :e2e] do
    test "the #{env} server's config binds loopback only" do
      http = booted_config(unquote(env))[Endpoint][:http]

      assert http[:ip] == @loopback
      refute :inet6 in http
    end
  end

  test "the running server listens on loopback and nowhere else" do
    assert {:ok, {@loopback, port}} = Endpoint.server_info(:http)

    assert {:ok, socket} = :gen_tcp.connect(@loopback, port, [], 1_000)
    :gen_tcp.close(socket)

    # An address the config does not name, standing in for another interface.
    # Refused on Linux; macOS has no such alias, so there it may time out.
    assert {:error, _} = :gen_tcp.connect({127, 0, 0, 2}, port, [], 1_000)
    assert {:error, _} = :gen_tcp.connect({0, 0, 0, 0, 0, 0, 0, 1}, port, [:inet6], 1_000)
  end

  test "only the e2e build compiles the fixture routes in" do
    assert compile_config(:e2e)[:e2e_project][:sql_sandbox] == true

    for env <- [:test, :dev, :staging, :prod] do
      refute compile_config(env)[:e2e_project][:sql_sandbox], "#{env} would compile the fixture routes in"
    end

    # This test runs in MIX_ENV=test. GET falls through to the pages' catch-all.
    assert Phoenix.Router.route_info(Router, "POST", "/e2e/login/someone@example.com", "") == :error
    assert %{plug: E2eProjectWeb.PageController} = Phoenix.Router.route_info(Router, "GET", "/__e2e/db/factory", "")
  end
end
