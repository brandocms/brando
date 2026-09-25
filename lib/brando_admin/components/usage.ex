defmodule BrandoAdmin.Components.Usage do
  @moduledoc """
  Shows where an asset is used (see `Brando.Content.Usage`).

    * `inline/1` — one line for a listing row: "Used in Sommerro, About".
    * `list/1` — a section for an asset's own page: one linked row per entry,
      with its cover, type and status.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  import Brando.HTML.Icon, only: [icon: 1]

  @doc """
  One line for a listing row. `usages` is `nil` while unknown, which renders
  nothing, so a listing without the lookup stays quiet.
  """
  attr :usages, :list, default: nil

  def inline(assigns) do
    ~H"""
    <div :if={is_list(@usages)} class="usage-inline">
      <%= if @usages == [] do %>
        <span class="usage-unused">{gettext("Not in use")}</span>
      <% else %>
        <span>{gettext("Used in")}</span>
        <span :for={{usage, index} <- Enum.with_index(@usages)} class="usage-inline-entry">
          <.link :if={usage.url} navigate={usage.url}>{usage.label}</.link><span :if={!usage.url}>{usage.label}</span><span
            :if={index < length(@usages) - 1}
            aria-hidden="true"
          >,</span>
        </span>
      <% end %>
    </div>
    """
  end

  @doc """
  A section for an asset's own page, listing the entries using it. Says so
  when it is used nowhere.
  """
  attr :usages, :list, required: true
  attr :id, :string, default: "usage"

  def list(assigns) do
    ~H"""
    <section class="usage-list" aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"}>{gettext("Used in")}</h2>
      <p :if={@usages == []} class="usage-list-empty">{gettext("Not in use anywhere yet.")}</p>
      <ul :if={@usages != []}>
        <li :for={usage <- @usages}>
          <.link :if={usage.url} navigate={usage.url}><.row usage={usage} /></.link>
          <div :if={!usage.url}><.row usage={usage} /></div>
        </li>
      </ul>
    </section>
    """
  end

  attr :usage, :map, required: true

  defp row(assigns) do
    ~H"""
    <span class="usage-cover"><img :if={@usage.cover} src={@usage.cover} alt="" loading="lazy" /></span>
    <span class="usage-label">{@usage.label}</span>
    <span class="usage-type">{@usage.type}</span>
    <span
      class={["usage-status", @usage.status && "status-#{@usage.status}"]}
      title={@usage.status && to_string(@usage.status)}
    ></span>
    <.icon name="hero-arrow-right" class={!@usage.url && "hidden"} />
    """
  end
end
