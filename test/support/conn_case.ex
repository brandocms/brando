defmodule Brando.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  imports other functionality to make it easier
  to build and query models.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest

      # Alias the data repository and import query/model functions
      alias Brando.Integration.TestRepo
      import Ecto.Model
      import Ecto.Query, only: [from: 2]

      # Import URL helpers from the router
      alias RouterHelper.TestRouter.Helpers

      # The default endpoint for testing
      @endpoint Brando.endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.Integration.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Brando.Integration.TestRepo, {:shared, self()})
    end

    :ok
  end
end
