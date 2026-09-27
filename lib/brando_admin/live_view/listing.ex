defmodule BrandoAdmin.LiveView.Listing do
  @moduledoc """
  Public setup API for Brando admin listing LiveViews.

  Use the stable entry point in application code:

      use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project

  A screen that uses a schema's listing machinery but is about something else
  (a curator, a dashboard) can name its tab:

      use BrandoAdmin.LiveView.Listing, schema: MyApp.Works.Feature, page_title: "Front page"

  `page_title` is a string, or a zero-arity function for a translated one
  (`page_title: &__MODULE__.page_title/0`). Without it the tab is the schema's
  plural.

  Compiler and hook modules are internal implementation details.
  """

  @hooks Module.concat(["BrandoAdmin", "LiveView", "Listing", "Hooks"])

  @doc false
  defmacro __using__(opts), do: BrandoAdmin.LiveView.Listing.Compiler.build(opts)

  @doc false
  def hooks(params, session, socket, schema) do
    call_hooks(:hooks, [params, session, socket, schema])
  end

  @doc false
  def put_page_title({:cont, socket}, nil), do: {:cont, socket}

  def put_page_title({:cont, socket}, title) when is_function(title, 0),
    do: {:cont, Phoenix.Component.assign(socket, :page_title, title.())}

  def put_page_title({:cont, socket}, title) when is_binary(title),
    do: {:cont, Phoenix.Component.assign(socket, :page_title, title)}

  def put_page_title(result, _title), do: result

  @doc "Refreshes every mounted listing for the given schema."
  def update_list_entries(schema), do: call_hooks(:update_list_entries, [schema])

  defp call_hooks(function, arguments), do: apply(@hooks, function, arguments)
end
