defmodule Brando.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

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

      # Alias the data repository and import query/schema functions
      alias BrandoIntegration.Repo
      import Ecto.Schema
      import Ecto.Query, only: [from: 2]

      # Import URL helpers from the router
      alias BrandoIntegrationWeb.Router.Helpers

      # The default endpoint for testing
      @endpoint Brando.endpoint()
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(BrandoIntegration.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(BrandoIntegration.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
