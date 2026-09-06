defmodule BrandoAdmin.LiveView.Listing.Compiler do
  @moduledoc """
  Internal compiler for the public `BrandoAdmin.LiveView.Listing` API. It expands the
  shared LiveView setup without depending on the runtime listing hook implementation.

  Listing LiveViews keep using the public entry point:

      use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project
  """

  defmacro __using__(opts), do: build(opts)

  @doc "Builds the setup expanded by the public listing LiveView API."
  def build(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      use BrandoAdmin, :live_view

      def __authorization_resource__, do: {:listing, unquote(schema)}
      import Phoenix.Component

      on_mount({__MODULE__, :hooks})

      def on_mount(:hooks, params, assigns, socket) do
        BrandoAdmin.LiveView.Listing.Hooks.hooks(params, assigns, socket, unquote(schema))
      end
    end
  end
end
