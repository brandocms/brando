defmodule BrandoAdmin.LiveView.Listing.Compiler do
  @moduledoc """
  Internal compiler for the public `BrandoAdmin.LiveView.Listing` API. It expands the
  shared LiveView setup without depending on the runtime listing hook implementation.

  Listing LiveViews keep using the public entry point:

      use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project
  """

  # Each Delete permanently, and the deletes that ask for step-up on it. A
  # selection of one row is that row, so the selection asks as the row does.
  @permanent_deletes [
    {"delete_entry_permanently", ~w(delete_entry)},
    {"delete_selected_permanently", ~w(delete_entry delete_selected)}
  ]

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

      @doc false
      def __deletes_permanently__,
        do: BrandoAdmin.LiveView.Listing.Hooks.deletes_permanently?(unquote(overrides))

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
  The `step_up` events with Delete permanently in the trash: the row's asks
  when `delete_entry` does, the selection's when `delete_entry` or
  `delete_selected` does.
  """
  def with_permanent_deletes(step_up) do
    permanent = for {permanent, deletes} <- @permanent_deletes, Enum.any?(deletes, &(&1 in step_up)), do: permanent
    Enum.uniq(step_up ++ permanent)
  end
end
