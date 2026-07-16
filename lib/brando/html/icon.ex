defmodule Brando.HTML.Icon do
  @moduledoc """
  Lightweight icon component shared by front-end and admin rendering.

  Keeping this primitive separate lets low-level callers render icons without
  depending on the full `Brando.HTML` convenience module.
  """

  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :any, default: nil

  @doc """
  Renders a CSS-backed icon.

  Heroicons use `hero-*` names and may select solid or mini variants with the
  corresponding suffix.

  ## Examples

      <Brando.HTML.Icon.icon name="hero-x-mark-solid" />
      <Brando.HTML.Icon.icon name="hero-arrow-path" class="w-3 animate-spin" />
  """
  def icon(assigns) do
    ~H"""
    <span data-icon class={[@name, @class]} />
    """
  end
end
