defmodule BrandoAdmin.Components.Content.List.Row.Status do
  use Surface.Component
  import Brando.Gettext

  prop entry, :any, required: true
  prop soft_delete?, :boolean, required: true
  data json_statuses, :string

  def mount(socket) do
    {:ok, assign(socket, :json_statuses, json_statuses())}
  end

  def render(assigns) do
    ~F"""
    {#if @soft_delete? and @entry.deleted_at}
      <div class="status">
        <div center="true">
          <svg data-testid="status-deleted" xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 15 15"><circle r="7.5" cy="7.5" cx="7.5" class="deleted"></circle></svg>
        </div>
      </div>
    {#elseif @entry.status == :pending and @entry.publish_at}
      <div class="status">
        <div
          id={"entry_status_#{@entry.id}"}
          data-statuses={@json_statuses}
          phx-hook="Brando.StatusDropdown"
          phx-value-id={@entry.id}>
          <svg data-testid="status-pending" width="15" height="15" viewBox="0 0 15 15" fill="none" xmlns="http://www.w3.org/2000/svg">
            <circle class="pending" cx="7.5" cy="7.5" r="7.5" />
            <line x1="7.5" y1="3" x2="7.5" y2="7" stroke="white" />
            <line x1="3.5" y1="7.5" x2="8" y2="7.5" stroke="white" />
          </svg>
        </div>
      </div>
    {#else}
      <div class="status">
        <div
          id={"entry_status_#{@entry.id}"}
          data-statuses={json_statuses()}
          phx-hook="Brando.StatusDropdown"
          phx-value-id={@entry.id}>
          <svg
            data-testid={"status-#{@entry.status}"}
            xmlns="http://www.w3.org/2000/svg"
            width="15"
            height="15"
            viewBox="0 0 15 15"><circle r="7.5" cy="7.5" cx="7.5" class={@entry.status}"></circle></svg>
        </div>
      </div>
    {/if}
    """
  end

  defp json_statuses() do
    [:published, :disabled, :draft, :pending]
    |> Enum.map(&{&1, render_status_label(&1)})
    |> Jason.encode!()
  end

  defp render_status_label(:disabled), do: gettext("Disabled")
  defp render_status_label(:draft), do: gettext("Draft")
  defp render_status_label(:pending), do: gettext("Pending")
  defp render_status_label(:published), do: gettext("Published")
  defp render_status_label(:deleted), do: gettext("Deleted")
end
