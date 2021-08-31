defmodule BrandoAdmin.Components.Content.List.Row.Creator do
  use Surface.Component

  prop entry, :any, required: true
  prop soft_delete?, :boolean, required: true

  def render(assigns) do
    ~F"""
    <div class="col-4">
      <article class="item-meta">
        <section class="avatar-wrapper">
          <div class="avatar">
            <img src={"/media/#{Map.get(@entry.creator.avatar.sizes, "thumb")}"}>
          </div>
        </section>
        <section class="content">
          <div class="info">
            <div class="name">
              {@entry.creator.name}
            </div>

            <div
              class="time"
              id={"entry_creator_time_icon_#{@entry.id}"}
              phx-hook="Brando.Popover"
              data-popover={"The time the entry was #{@soft_delete? and @entry.deleted_at && "deleted" || "created"}"}>
              {#if @soft_delete? and @entry.deleted_at}
                {Calendar.strftime(@entry.deleted_at, "%d/%m/%y")} <span>•</span> {Calendar.strftime(@entry.deleted_at, "%H:%M")}
              {#else}
                {Calendar.strftime(@entry.updated_at, "%d/%m/%y")} <span>•</span> {Calendar.strftime(@entry.updated_at, "%H:%M")}
              {/if}
            </div>
          </div>
        </section>
      </article>
    </div>
    """
  end
end
