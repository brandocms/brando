defmodule Brando.Exception.MissingTenantError do
  @moduledoc """
  Raised by `Brando.Repo` for a query on a site's table with no tenant prefix
  in multi-site mode. The `public` copy of such a table is not any site's
  content: run the query inside `Brando.Tenant.with_prefix/2`, or pass
  `prefix: "public"` where the public copy is meant.
  """
  defexception [:table]

  @impl true
  def message(%{table: table}) do
    "query on the site table #{inspect(table)} without a tenant prefix in multi-site mode; " <>
      "run it inside Brando.Tenant.with_prefix/2, or pass prefix: \"public\" for the public copy"
  end
end
