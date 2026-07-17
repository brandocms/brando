defmodule BrandoAdmin.LiveView.Listing do
  @moduledoc """
  Public setup API for Brando admin listing LiveViews.

  Use the stable entry point in application code:

      use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project

  Compiler and hook modules are internal implementation details.
  """

  @hooks Module.concat(["BrandoAdmin", "LiveView", "Listing", "Hooks"])

  @doc false
  defmacro __using__(opts), do: BrandoAdmin.LiveView.Listing.Compiler.build(opts)

  @doc false
  def hooks(params, session, socket, schema) do
    call_hooks(:hooks, [params, session, socket, schema])
  end

  @doc "Refreshes every mounted listing for the given schema."
  def update_list_entries(schema), do: call_hooks(:update_list_entries, [schema])

  defp call_hooks(function, arguments), do: apply(@hooks, function, arguments)
end
