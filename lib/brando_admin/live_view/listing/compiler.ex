defmodule BrandoAdmin.LiveView.Listing.Compiler do
  @moduledoc """
  Compiles the shared admin listing LiveView setup without depending on the
  runtime listing hook implementation.

  Use this module when defining listing LiveViews:

      use BrandoAdmin.LiveView.Listing.Compiler, schema: MyApp.Projects.Project
  """

  defmacro __using__(opts), do: build(opts)

  @doc "Builds the listing LiveView setup used by focused and compatibility macros."
  def build(opts) do
    schema = Keyword.fetch!(opts, :schema)

    quote do
      use BrandoAdmin, :live_view
      import Phoenix.Component

      on_mount({__MODULE__, :hooks})

      def on_mount(:hooks, params, assigns, socket) do
        BrandoAdmin.LiveView.Listing.hooks(params, assigns, socket, unquote(schema))
      end
    end
  end
end
