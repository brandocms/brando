defmodule Brando.Blueprint.Listings.Components do
  @moduledoc """
  Reusable components for custom Blueprint listing rows.

  Import this module only in Blueprints that define a custom listing row:

      import Brando.Blueprint.Listings.Components

  Keeping the import local avoids coupling every Blueprint schema to the admin
  rendering tree.
  """
  use Phoenix.Component

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

  @doc "Renders an image cover cell."
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

  @doc "Renders a published entry's front-end URL action."
  def url(assigns) do
    entry = assigns.entry

    assigns =
      assigns
      |> assign(:status, Map.get(assigns.entry, :status))
      |> assign(:href, Brando.Blueprint.URL.resolve(entry))

    ~H"""
    <div class={[
      @class,
      "col-1",
      "url",
      @offset && "offset-#{@offset}"
    ]}>
      <a :if={@status == :published} href={@href} target="_blank">
        <Brando.HTML.Icon.icon name="hero-link" />
      </a>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :padded, :boolean, default: false
  attr :entry, :map, required: true
  attr :columns, :integer, required: true
  attr :offset, :integer, default: nil
  attr :skip_style, :boolean, default: false
  slot :inner_block
  slot :before
  slot :outside

  @doc "Renders a listing cell linked to the entry's admin update route."
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
      {render_slot(@before)}
      <.link navigate={@update_url} class={!@skip_style && "entry-link"}>
        {render_slot(@inner_block)}
      </.link>
      {render_slot(@outside)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :columns, :integer, required: true
  attr :offset, :integer, default: nil
  slot :inner_block

  @doc "Renders a generic listing grid cell."
  def field(assigns) do
    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :fields, :list, required: true
  attr :columns, :integer, default: 1
  attr :offset, :integer, default: nil

  @doc "Renders the child-listing action for an entry."
  def children_button(assigns) do
    ~H"""
    <div class={[
      @class,
      @columns && "col-#{@columns}",
      @offset && "offset-#{@offset}"
    ]}>
      <.live_component module={ChildrenButton} id={"#{@entry.id}-children-button"} fields={@fields} entry={@entry} />
    </div>
    """
  end

  attr :map, :any, required: true

  @doc "Renders the current locale's value from a translated map."
  def i18n(assigns), do: Brando.HTML.I18n.i18n(assigns)
end
