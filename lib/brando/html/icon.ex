defmodule Brando.HTML.Icon do
  @moduledoc """
  Lightweight icon component shared by front-end and admin rendering.

  Keeping this primitive separate lets low-level callers render icons without
  depending on the full `Brando.HTML` convenience module.
  """

  use Phoenix.Component

  require Logger

  @fallback "circle-question-mark"

  attr :name, :string, required: true, doc: "a Lucide icon name, such as `house`"
  attr :class, :any, default: nil
  attr :rest, :global

  @doc """
  Renders a [Lucide](https://lucide.dev/icons) icon.

  The icon is a `<span>` masked by the stylesheet `Brando.Icons` generates, so
  size it with `width`/`height` and colour it with `color`. Legacy `hero-*`
  names still render through `Brando.Icons.resolve/1`. An unknown name renders
  a question mark and logs a warning once.

  ## Examples

      <Brando.HTML.Icon.icon name="x" />
      <Brando.HTML.Icon.icon name="refresh-cw" class="animate-spin" />
  """
  def icon(assigns) do
    assigns = assign(assigns, :icon, resolve(assigns.name))

    ~H"""
    <span data-icon class={["lucide-" <> @icon, @class]} {@rest} />
    """
  end

  defp resolve(name) do
    case Brando.Icons.resolve(name) do
      {:ok, icon} ->
        icon

      :error ->
        warn_once(name)
        @fallback
    end
  end

  defp warn_once(name) do
    key = {__MODULE__, :warned, name}

    if not :persistent_term.get(key, false) do
      :persistent_term.put(key, true)
      Logger.warning("[Brando.HTML.Icon] unknown icon #{inspect(name)}, rendering #{@fallback}")
    end
  end
end
