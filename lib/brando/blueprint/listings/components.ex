defmodule Brando.Blueprint.Listings.Components do
  @moduledoc """
  Compatibility facade for custom Blueprint listing-row components.

  Existing imports remain supported:

      import Brando.Blueprint.Listings.Components

  For a narrower dependency graph, import the lightweight core and only the
  optional components a row uses:

      import Brando.Blueprint.Listings.Components.Core
      import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]
      import Brando.Blueprint.Listings.Components.Children, only: [children_button: 1]
  """
  use Phoenix.Component

  alias Brando.Blueprint.Listings.Components.Children
  alias Brando.Blueprint.Listings.Components.Core
  alias Brando.Blueprint.Listings.Components.Cover

  attr :class, :any, default: nil
  attr :padded, :boolean, default: false
  attr :circular, :boolean, default: false
  attr :image, :map, required: true
  attr :columns, :integer, required: true
  attr :size, :atom, default: :thumb
  attr :offset, :integer, default: nil
  attr :top, :boolean, default: false

  @doc "Renders an image cover cell."
  def cover(assigns), do: Cover.cover(assigns)

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :offset, :integer, default: nil

  @doc "Renders a published entry's front-end URL action."
  def url(assigns), do: Core.url(assigns)

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
  def update_link(assigns), do: Core.update_link(assigns)

  attr :class, :any, default: nil
  attr :columns, :integer, required: true
  attr :offset, :integer, default: nil
  slot :inner_block

  @doc "Renders a generic listing grid cell."
  def field(assigns), do: Core.field(assigns)

  attr :class, :any, default: nil
  attr :entry, :map, required: true
  attr :fields, :list, required: true
  attr :columns, :integer, default: 1
  attr :offset, :integer, default: nil

  @doc "Renders the child-listing action for an entry."
  def children_button(assigns), do: Children.children_button(assigns)

  attr :map, :any, required: true

  @doc "Renders the current locale's value from a translated map."
  def i18n(assigns), do: Core.i18n(assigns)
end
