defmodule BrandoAdmin.Components.Content.List.Row.Creator do
  use Surface.Component
  import Brando.Utils.Datetime

  prop entry, :any, required: true
  prop soft_delete?, :boolean, required: true

  data avatar, :string

  def render(%{entry: %{creator: %{avatar: avatar}}} = assigns) do
    assigns =
      assigns
      |> assign(
        :avatar,
        Brando.Utils.img_url(avatar, :thumb,
          prefix: "/media",
          default: "/images/admin/avatar.svg"
        )
      )

    ~F"""
    <div class="col-4">
      <article class="item-meta">
        <section class="avatar-wrapper">
          <div class="avatar">
            <img src={@avatar}>
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
              data-popover={"The time the entry was #{@soft_delete? and @entry.deleted_at && "deleted" || "created"}"}>
              {#if @soft_delete? and @entry.deleted_at}
                {format_datetime(@entry.deleted_at, "%d/%m/%y")} <span>•</span> {format_datetime(@entry.deleted_at, "%H:%M")}
              {#else}
                {format_datetime(@entry.updated_at, "%d/%m/%y")} <span>•</span> {format_datetime(@entry.updated_at, "%H:%M")}
              {/if}
            </div>
          </div>
        </section>
      </article>
    </div>
    """
  end
end
