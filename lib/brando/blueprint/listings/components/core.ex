defmodule Brando.Blueprint.Listings.Components.Core do
  @moduledoc """
  Lightweight components used by most custom Blueprint listing rows.

  Import this module for grid fields, admin update links, front-end URL actions,
  and translated strings. Cover images and child-listing actions live in opt-in
  modules so ordinary rows do not inherit their admin rendering dependencies.
  """
  use Phoenix.Component

  alias Brando.Blueprint.URL
  alias Brando.HTML.I18n
  alias Brando.HTML.Icon

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :offset, :integer, default: nil

  @doc "Renders a published entry's front-end URL action."
  def url(assigns) do
    assigns =
      assigns
      |> assign(:status, Map.get(assigns.entry, :status))
      |> assign(:href, URL.resolve(assigns.entry))

    ~H"""
    <div class={[
      @class,
      "col-1",
      "url",
      @offset && "offset-#{@offset}"
    ]}>
      <a :if={@status == :published} href={@href} target="_blank">
        <Icon.icon name="hero-link" />
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

  attr :map, :any, required: true

  @doc "Renders the current locale's value from a translated map."
  def i18n(assigns), do: I18n.i18n(assigns)
end
