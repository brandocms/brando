defmodule BrandoAdmin.Components.Content.Identifier do
  @moduledoc "Shared identifier contents for selected entries and picker results."
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  attr :identifier, :map, required: true
  attr :draggable, :boolean, default: false
  attr :selectable, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :show_url, :boolean, default: false
  slot :inner_block
  slot :delete

  def content(assigns) do
    identifier = assigns.identifier

    assigns =
      assigns
      |> assign(:type, Brando.Blueprint.get_singular(identifier.schema))
      |> assign(:cover, Map.get(identifier, :cover))
      |> assign(:language, Map.get(identifier, :language))
      |> assign(:status, Map.get(identifier, :status))
      |> assign(:url, Map.get(identifier, :url))

    ~H"""
    <span :if={@draggable} class="identifier-grip" aria-hidden="true">
      <i></i><i></i><i></i><i></i><i></i><i></i>
    </span>
    <span class="identifier-cover">
      <%= if is_binary(@cover) && @cover != "" do %>
        <img src={@cover} alt="" loading="lazy" draggable="false" />
      <% else %>
        <.icon name="hero-document-text" />
      <% end %>
    </span>
    <span class="identifier-copy">
      {render_slot(@inner_block)}
      <span class="identifier-title">{@identifier.title}</span>
      <span :if={@show_url && @url not in [nil, ""]} class="identifier-url">{@url}</span>
      <span class="identifier-details">
        <span class="identifier-type">{@type}</span>
        <span :if={@language} class="identifier-language">{String.upcase(to_string(@language))}</span>
        <span class="identifier-status" data-status={@status}>
          <i aria-hidden="true"></i>{status_label(@status)}
        </span>
      </span>
    </span>
    <span :if={@selectable} class="identifier-check" aria-hidden="true">
      <.icon :if={@selected} name="hero-check" />
    </span>
    <span :if={@delete != []} class="identifier-remove remove">{render_slot(@delete)}</span>
    """
  end

  defp status_label(:published), do: gettext("Published")
  defp status_label(:draft), do: gettext("Draft")
  defp status_label(:pending), do: gettext("Pending")
  defp status_label(:disabled), do: gettext("Disabled")
  defp status_label(:deleted), do: gettext("Deleted")
  defp status_label(_), do: gettext("Not set")
end
