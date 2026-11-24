defmodule BrandoAdmin.LiveView.Listing.Compiler do
  @moduledoc """
  Internal compiler for the public `BrandoAdmin.LiveView.Listing` API. It expands the
  shared LiveView setup without depending on the runtime listing hook implementation.

  Listing LiveViews keep using the public entry point:

      use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project
  """

  @permanent_deletes [{"delete_entry", "delete_entry_permanently"}, {"delete_selected", "delete_selected_permanently"}]

  defmacro __using__(opts), do: build(opts)

  @doc "Builds the setup expanded by the public listing LiveView API."
  def build(opts) do
    schema = Keyword.fetch!(opts, :schema)
    page_title = Keyword.get(opts, :page_title)
    step_up = Keyword.get(opts, :step_up, [])
    overrides = Keyword.get(opts, :overrides, [])

    reauth =
      if step_up != [] do
        quote do
          # Ahead of the listing's hooks, so that it holds the listing's own
          # events as well as the view's
          on_mount(
            {BrandoAdmin.Reauth,
             events: BrandoAdmin.LiveView.Listing.Compiler.with_permanent_deletes(unquote(step_up)),
             replay: {BrandoAdmin.LiveView.Listing.Hooks, :replay_event, [unquote(schema), unquote(overrides)]}}
          )
        end
      end

    quote do
      use BrandoAdmin, :live_view

      def __authorization_resource__, do: {:listing, unquote(schema)}
      import Phoenix.Component

      unquote(reauth)
      on_mount({__MODULE__, :hooks})

      def on_mount(:hooks, params, assigns, socket) do
        params
        |> BrandoAdmin.LiveView.Listing.Hooks.hooks(assigns, socket, unquote(schema), unquote(overrides))
        |> BrandoAdmin.LiveView.Listing.put_page_title(unquote(page_title))
      end
    end
  end

  @doc """
  The `step_up` events with Delete permanently in the trash, which asks as
  the delete it stands in for does.
  """
  def with_permanent_deletes(step_up) do
    permanent = for {event, permanent} <- @permanent_deletes, event in step_up, do: permanent
    Enum.uniq(step_up ++ permanent)
  end
end
