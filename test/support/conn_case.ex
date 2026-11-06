defmodule Brando.ConnCase do
  @moduledoc """
  Use this case template for tests that need a Plug connection and
  transactional database access.

  Such tests rely on `Phoenix.ConnTest` and also
  imports other functionality to make it easier
  to build and query schema data.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Brando.Test.Support

      # Alias the data repository and import query/schema functions
      alias BrandoIntegration.Repo
      import Ecto.Schema
      import Ecto.Query, only: [from: 2]

      # Import URL helpers from the router
      alias BrandoIntegrationWeb.Router.Helpers
      use Oban.Testing, repo: BrandoIntegration.Repo

      # The default endpoint for testing
      @endpoint Brando.endpoint()
    end
  end

  setup tags do
    setup_sandbox(tags)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def setup_sandbox(tags) do
    # Registered first, so it runs after everything else on exit. Async tests
    # share the cache with each other while they run.
    unless tags[:async], do: Brando.Test.Support.preserve_tenant_query_cache()
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(BrandoIntegration.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # The query cache entries this test makes are its own (Brando.Test.ScopedEnv)
    owner = self()
    :ok = Brando.Test.ScopedEnv.own_cache()
    on_exit(fn -> Brando.Test.ScopedEnv.delete(owner, :cache_owner) end)
  end
end
