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
      |> assign(:icon, Brando.Blueprint.get_icon(identifier.schema))
      |> assign(:cover, Map.get(identifier, :cover))
      |> assign(:language, Map.get(identifier, :language))
      |> assign(:status, Map.get(identifier, :status))

    ~H"""
    <span :if={@draggable} class="identifier-grip" aria-hidden="true">
      <i></i><i></i><i></i><i></i><i></i><i></i>
    </span>
    <span class="identifier-cover">
      <%= if is_binary(@cover) && @cover != "" do %>
        <img src={@cover} alt="" loading="lazy" draggable="false" />
      <% else %>
        <.icon name={@icon} />
      <% end %>
    </span>
    <span class="identifier-copy">
      {render_slot(@inner_block)}
      <%!-- Status is the dot before the title; its name is there for screen
            readers and on hover. --%>
      <span class="identifier-title">
        <span class="identifier-status" data-status={@status} title={status_label(@status)}>
          <i aria-hidden="true"></i><span class="visually-hidden">{status_label(@status)}</span>
        </span>
        {@identifier.title}
      </span>
      <.destination :if={@show_url} identifier={@identifier} class="identifier-url" />
      <span class="identifier-details">
        <span class="identifier-type">{@type}</span>
        <span :if={@language} class="identifier-language">{String.upcase(to_string(@language))}</span>
      </span>
    </span>
    <span :if={@selectable} class="identifier-check" aria-hidden="true">
      <.icon :if={@selected} name="check" />
    </span>
    <span :if={@delete != []} class="identifier-remove remove">{render_slot(@delete)}</span>
    """
  end

  @doc """
  Where a link to the entry goes: its path on this site, or, for an entry its
  blueprint links elsewhere (`absolute_url ..., link_others_to:`), an arrow and
  the destination's host, with the whole address on hover.
  """
  attr :identifier, :map, required: true
  attr :class, :any, default: nil

  def destination(assigns) do
    url = Map.get(assigns.identifier, :url)
    external_url = Map.get(assigns.identifier, :external_url)

    assigns =
      assigns
      |> assign(:url, url not in [nil, ""] && url)
      |> assign(:external_url, url in [nil, ""] && external_url not in [nil, ""] && external_url)

    ~H"""
    <span :if={@url} class={@class}>{@url}</span>
    <span :if={@external_url} class={[@class, "identifier-external"]} title={@external_url}>
      <.icon name="external-link" /><span class="visually-hidden">{gettext("Links elsewhere:")}</span>
      {host(@external_url)}
    </span>
    """
  end

  defp host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.replace_prefix(host, "www.", "")
      _ -> url
    end
  end

  @doc "The status's name, for screen readers and the dot's tooltip."
  def status_label(:published), do: gettext("Published")
  def status_label(:draft), do: gettext("Draft")
  def status_label(:pending), do: gettext("Pending")
  def status_label(:disabled), do: gettext("Disabled")
  def status_label(:deleted), do: gettext("Deleted")
  def status_label(_), do: gettext("Not set")
end
