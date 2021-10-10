defmodule BrandoAdmin.Components.Content.List.Tools do
  use Surface.Component
  import Brando.Gettext
  alias Surface.Components.Form
  alias BrandoAdmin.Components.Content.List.Tools.ActiveFilters

  prop schema, :module
  prop listing, :any
  prop active_filter, :any
  prop list_opts, :any
  prop update_status, :event, required: true
  prop update_filter, :event, required: true
  prop delete_filter, :event, required: true
  prop next_filter_key, :event, required: true

  data statuses, :list
  data filters, :list
  data has_status?, :boolean

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:active_filter, assigns.active_filter)
     |> assign(:list_opts, assigns.list_opts)
     |> assign(:has_status?, assigns.schema.has_trait(Brando.Trait.Status))
     |> assign_new(:schema, fn -> assigns.schema end)
     |> assign_new(:listing, fn -> assigns.listing end)
     |> assign_new(:update_filter, fn -> assigns.update_filter end)
     |> assign_new(:delete_filter, fn -> assigns.delete_filter end)
     |> assign_new(:update_status, fn -> assigns.update_status end)
     |> assign_new(:next_filter_key, fn -> assigns.next_filter_key end)
     |> assign_new(:statuses, fn -> get_statuses(assigns.schema) end)
     |> assign_new(:filters, fn -> assigns.listing.filters end)}
  end

  def render(assigns) do
    ~F"""
    <div class="list-tools-wrapper">
      <div class="list-tools">
        {#if @has_status?}
          <div class="statuses">
            {#for status <- @statuses}
              <button
                :on-click={@update_status}
                phx-value-status={status}
                class={
                  "status",
                  active_status_class(@list_opts, status)
                }
                type="button"
                phx-page-loading>
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="12"
                  height="12"
                  viewBox="0 0 12 12">
                  <circle
                    class={status}
                    r="6"
                    cy="6"
                    cx="6" />
                </svg>
                <span class="label">{render_status_label(status)}</span>
              </button>
            {/for}
          </div>
        {/if}

        <div class="filters">
          {#for filter <- @filters}
            <div class={
              "filter",
              visible: filter[:filter] == @active_filter[:filter]
            }>
              <button
                class="filter-key"
                :on-click={@next_filter_key}>
                {filter[:label]}
              </button>
              <Form
                for={:filter_form}
                change={@update_filter}
                opts={onkeydown: "return event.key != 'Enter';"}>
                <input
                  type="text"
                  name="q"
                  value=""
                  placeholder={gettext("Filter")}
                  autocomplete="off"
                  phx-debounce="400"
                />
                <input
                  type="hidden"
                  name="filter"
                  value={@active_filter[:filter]}
                />
              </Form>
            </div>
          {/for}
        </div>
      </div>

      {#if @list_opts[:filter]}
        <ActiveFilters
          active_filters={@list_opts[:filter]}
          filters={@filters}
          delete={@delete_filter} />
      {/if}
    </div>
    """
  end

  defp get_statuses(schema) do
    soft_delete? = schema.has_trait(SoftDelete)

    if soft_delete? do
      [:published, :disabled, :draft, :pending, :deleted]
    else
      [:published, :disabled, :draft, :pending]
    end
  end

  defp active_status_class(list_opts, status) do
    if active_status?(list_opts, status) do
      " active"
    else
      ""
    end
  end

  defp active_status?(%{status: current_status}, status) when current_status == status, do: true
  defp active_status?(_, _), do: false

  defp render_status_label(:disabled), do: gettext("Disabled")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")
end
