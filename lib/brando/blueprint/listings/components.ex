defmodule Brando.Blueprint.Listings.Components do
  @moduledoc """
  Components to use in listings
  """
  use Phoenix.Component
  import Brando.HTML, only: [icon: 1]
  alias BrandoAdmin.Components.ChildrenButton
  alias BrandoAdmin.Components.Content

  attr :class, :any, default: nil
  attr :padded, :boolean, default: false
  attr :circular, :boolean, default: false
  attr :image, :map, required: true
  attr :columns, :integer, required: true
  attr :size, :atom, default: :thumb
  attr :offset, :integer, default: nil
  attr :top, :boolean, default: false

  def cover(assigns) do
    ~H"""
    <div class={[
      "cover",
      @class,
      @padded && "padded",
      @circular && "circular",
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}",
      @top && "top"
    ]}>
      <Content.image image={@image} size={@size} />
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :offset, :integer, default: nil

  def url(assigns) do
    entry = assigns.entry

    assigns =
      assigns
      |> assign(:status, Map.get(assigns.entry, :status))
      |> assign(:href, Brando.HTML.absolute_url(entry))

    ~H"""
    <div class={[
      @class,
      "col-1",
      "url",
      @offset && "offset-#{@offset}"
    ]}>
      <a :if={@status == :published} href={@href} target="_blank">
        <.icon name="hero-link" />
      </a>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :padded, :boolean, default: false
  attr :entry, :map, required: true
  attr :columns, :integer, required: true
  attr :offset, :integer, default: nil
  slot :inner_block
  slot :outside

  def update_link(assigns) do
    schema = assigns.entry.__struct__
    update_url = schema.__admin_route__(:update, [assigns.entry.id])
    assigns = assign(assigns, :update_url, update_url)

    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <.link navigate={@update_url} class="entry-link">
        <%= render_slot(@inner_block) %>
      </.link>
      <%= render_slot(@outside) %>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :columns, :integer, required: true
  attr :offset, :integer, default: nil
  slot :inner_block

  def field(assigns) do
    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :fields, :list, required: true
  attr :columns, :integer, default: 1
  attr :offset, :integer, default: nil

  def children_button(assigns) do
    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <.live_component
        module={ChildrenButton}
        id={"#{@entry.id}-children-button"}
        fields={@fields}
        entry={@entry}
      />
    </div>
    """
  end

  defdelegate i18n(assigns), to: Brando.HTML
end
