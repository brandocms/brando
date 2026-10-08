defmodule BrandoAdmin.Components.AIAction do
  @moduledoc """
  The one look for an action that asks AI for something: the sparkles icon,
  the AI violet's ink and a solid violet hairline (`.ai-action` in
  `assets/css/components/AI.css`). The violet (`--brando-ai`) marks every
  call to an external, paid AI service.

      <AIAction.button phx-click="suggest_alt_text" phx-target={@myself}>
        {gettext("Suggest alt text")}
      </AIAction.button>

      <AIAction.button href={@url} target="_blank" rel="noopener">
        {gettext("Build with AI")}
      </AIAction.button>

  With `href` it renders a link, otherwise a `type="button"`. `size` is
  `:default` (30px), `:compact` (24px, beside a field's label) or `:icon`
  (28px square inside a text field; give it an `aria-label`). `variant`
  `:primary` fills it, for the confirm step of a costed request after its
  estimate ("Describe 3 images"). `busy` marks a request in flight. Put the label in the inner block; the icon is added.
  Anything else (`phx-*`, `disabled`, `data-*`, `aria-*`) is passed through.
  See "AI actions and suggestions" in `docs/admin-ui-design.md`.
  """
  use BrandoAdmin, :component

  attr :href, :string, default: nil
  attr :size, :atom, values: [:default, :compact, :icon], default: :default
  attr :variant, :atom, values: [:secondary, :primary], default: :secondary
  attr :busy, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled target rel title)
  slot :inner_block

  def button(%{href: href} = assigns) when is_binary(href) do
    ~H"""
    <.link href={@href} class={classes(@size, @variant, @busy, @class)} {@rest}>
      <.icon name="sparkles" />{render_slot(@inner_block)}
    </.link>
    """
  end

  def button(assigns) do
    ~H"""
    <button type="button" class={classes(@size, @variant, @busy, @class)} aria-busy={@busy && "true"} {@rest}>
      <.icon name="sparkles" />{render_slot(@inner_block)}
    </button>
    """
  end

  defp classes(size, variant, busy, class) do
    [
      "ai-action",
      size == :compact && "is-compact",
      size == :icon && "is-icon",
      variant == :primary && "is-primary",
      busy && "is-busy",
      class
    ]
  end
end
