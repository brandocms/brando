defmodule Brando.HTML.Services do
  @moduledoc """
  Renders the services configured on the identity as a visible section.

  Structured data mostly feeds AI retrieval; a site that also presents its
  services as real content gets more out of it, and it keeps the markup
  honest — Google asks that JSON-LD describe content that is on the page.
  Drop this where the services belong and the `Service` nodes the identity
  already emits describe that section.

      <Brando.HTML.Services.list language={@language}>
        <:heading>What we do</:heading>
      </Brando.HTML.Services.list>

  Pass `services` explicitly to render a subset, and an `:item` slot to
  control the markup of each entry. Only structural classes are emitted;
  the site styles it.
  """
  use Phoenix.Component

  alias Brando.Sites.Service

  attr :language, :string, default: nil, doc: "reads the cached identity for this language"
  attr :services, :list, default: nil, doc: "explicit services; overrides `language`"
  attr :class, :any, default: nil
  slot :heading
  slot :item, doc: "receives each service"

  def list(assigns) do
    assigns = assign(assigns, :entries, entries(assigns))

    ~H"""
    <section :if={@entries != []} class={["services", @class]}>
      <h2 :if={@heading != []} class="services-heading">{render_slot(@heading)}</h2>
      <ul class="services-list">
        <li :for={service <- @entries} class="service">
          <%= if @item != [] do %>
            {render_slot(@item, service)}
          <% else %>
            <h3 class="service-name">
              <a :if={url(service)} href={url(service)}>{service.name}</a>
              <span :if={!url(service)}>{service.name}</span>
            </h3>
            <p :if={description(service)} class="service-description">{description(service)}</p>
          <% end %>
        </li>
      </ul>
    </section>
    """
  end

  @doc "The resolved services for `language`, from the identity cache."
  @spec for_language(String.t() | atom() | nil) :: [Service.t()]
  def for_language(nil), do: []

  def for_language(language) do
    case Brando.Cache.Identity.get(to_string(language)) do
      %{services: services} when is_list(services) -> services
      _ -> []
    end
  end

  defp entries(%{services: services}) when is_list(services), do: services
  defp entries(%{language: language}), do: for_language(language)

  defp url(%{resolved_url: url}) when is_binary(url) and url != "", do: url
  defp url(%{url: url}) when is_binary(url) and url != "", do: url
  defp url(_), do: nil

  defp description(%{resolved_description: text}) when is_binary(text) and text != "", do: text
  defp description(%{description: text}) when is_binary(text) and text != "", do: text
  defp description(_), do: nil
end
