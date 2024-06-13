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
  attr :image, :map, required: true
  attr :columns, :integer, required: true
  attr :size, :atom, default: :thumb
  attr :offset, :integer, default: nil

  def cover(assigns) do
    ~H"""
    <div class={[
      @class,
      @padded && "padded",
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
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
  slot :default
  slot :outside

  def update_link(assigns) do
    schema = assigns.entry.__struct__

    update_url =
      Brando.routes().admin_live_path(
        Brando.endpoint(),
        schema.__modules__().admin_update_view,
        assigns.entry.id
      )

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
  attr :entry, :map, required: true
  attr :fields, :list, required: true
  attr :columns, :integer, default: 1
  attr :offset, :integer, default: nil
  slot :default
  slot :outside

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
end
