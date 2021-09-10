defmodule BrandoAdmin.Components.Content.List.Pagination do
  use Surface.Component
  import Brando.Gettext

  @doc "Pagination META information"
  prop pagination_meta, :any, required: true
  @doc "Event called on clicking a page number button"
  prop change_page, :event, required: true

  data current_page, :integer
  data total_pages, :integer
  data total_entries, :integer
  data showing_start, :integer
  data showing_end, :integer

  def update(
        %{
          pagination_meta: %{
            page_size: page_size,
            current_page: current_page,
            total_entries: total_entries,
            total_pages: total_pages
          },
          change_page: change_page
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(:change_page, change_page)
     |> assign(:current_page, current_page)
     |> assign(:total_entries, total_entries)
     |> assign(:total_pages, total_pages)
     |> assign(:showing_start, page_size * current_page - page_size + 1)
     |> assign(:showing_end, min(page_size * current_page, total_entries))}
  end

  def render(assigns) do
    ~F"""
    <div class="pagination">
      <div class="pagination-entries">
        &rarr; {@total_entries} {gettext("entries")}
        {#if @total_entries > 0}
        | {gettext("showing")} {@showing_start}-{@showing_end}
        {/if}
      </div>
      {#for p <- 0..@total_pages - 1}
        <button
          class={active: p + 1 == @current_page}
          :on-click={@change_page}
          phx-value-page={p}>
          {p + 1}
        </button>
      {/for}
    </div>
    """
  end
end
