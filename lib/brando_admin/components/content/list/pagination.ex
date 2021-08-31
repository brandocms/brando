defmodule BrandoAdmin.Components.Content.List.Pagination do
  use Surface.Component
  import Brando.Gettext

  @doc "Pagination META information"
  prop pagination_meta, :any, required: true
  @doc "Event called on clicking a page number button"
  prop change_page, :event, required: true

  def render(assigns) do
    ~F"""
    <div class="pagination">
      <div class="pagination-entries">
        &rarr; {@pagination_meta.total_entries} {gettext("entries")}
        {#if @pagination_meta.total_entries > 0}
        | showing {(@pagination_meta.page_size * @pagination_meta.current_page) - @pagination_meta.page_size + 1}-{min(@pagination_meta.page_size * @pagination_meta.current_page, @pagination_meta.total_entries)}
        {/if}
      </div>
      {#for p <- 0..@pagination_meta.total_pages - 1}
        <button
          class={active: p + 1 == @pagination_meta.current_page}
          :on-click={@change_page}
          phx-value-page={p}>
          {p + 1}
        </button>
      {/for}
    </div>
    """
  end
end
