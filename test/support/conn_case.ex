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
      import Brando.ConnCase

      # Alias the data repository and import query/schema functions
      alias Brando.Integration.Repo
      import Ecto.Schema
      import Ecto.Query, only: [from: 2]

      # Import URL helpers from the router
      alias Brando.Integration.Router.Helpers

      # The default endpoint for testing
      @endpoint Brando.endpoint()
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.Integration.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Brando.Integration.Repo, {:shared, self()})
    end

    :ok
  end
end
