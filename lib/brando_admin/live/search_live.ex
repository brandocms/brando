defmodule BrandoAdmin.SearchLive do
  @moduledoc """
  The search page, `/admin/search?q=…`: every entry the user may read whose
  title, slug, meta description, text fields or blocks match, ranked as
  `Brando.Search.Query` does, with filters for the content type, language
  and status, and pages of `BrandoAdmin.Search.page_size/0`.

  The command palette's "See all results" row opens it. Everything is in the
  URL, so a search can be shared and the browser's back button works.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content.List, as: ContentList
  alias BrandoAdmin.Search

  def __authorization__, do: {:access, :backend}

  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      socket = assign_new(socket, :current_user, fn -> Brando.Users.get_user_by_session_token(token) end)
      put_locale(socket.assigns.current_user)

      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:types, Search.types(socket.assigns.current_user))
       |> assign(:languages, Search.languages())
       |> assign(:statuses, Enum.map(Search.statuses(), &{&1, status_label(&1)}))
       |> assign(:sorts, [{"relevance", gettext("Best match")}, {"updated", gettext("Recently updated")}])}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  defp put_locale(%{language: language}) when not is_nil(language), do: Gettext.put_locale(to_string(language))
  defp put_locale(_), do: nil

  def handle_params(params, _url, %{assigns: %{socket_connected: true}} = socket) do
    filters = Search.filters(params, socket.assigns.types)

    results =
      if filters.q == "",
        do: %{rows: [], total: 0, facets: %{}},
        else: Search.results(socket.assigns.current_user, socket.assigns.types, filters)

    total_pages = max(div(results.total + Search.page_size() - 1, Search.page_size()), 1)

    {:noreply,
     socket
     |> assign(:page_title, page_title(filters.q))
     |> assign(:filters, filters)
     |> assign(:results, results)
     |> assign(:total_pages, total_pages)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp page_title(""), do: gettext("Search")
  defp page_title(q), do: gettext("Search: %{query}", query: q)

  # Any change starts again at the first page
  def handle_event("search", params, socket) do
    filters = Search.filters(Map.delete(params, "page"), socket.assigns.types)
    {:noreply, push_patch(socket, to: path(filters))}
  end

  defp path(filters) do
    case Search.query_string(filters) do
      "" -> "/admin/search"
      query -> "/admin/search?" <> query
    end
  end

  defp page_path(filters, page), do: path(%{filters | page: page})

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="search-workspace" id="search-workspace">
      <header class="search-heading">
        <h1>{gettext("Search")}</h1>
        <p>{gettext("Every entry you can read, by its title, address and content.")}</p>
      </header>

      <form id="search-form" class="search-toolbar" role="search" phx-change="search" phx-submit="search">
        <label class="search-query">
          <span class="visually-hidden">{gettext("Search for")}</span>
          <.icon name="search" />
          <input
            id="search-input"
            type="search"
            name="q"
            value={@filters.q}
            placeholder={gettext("Search titles and content")}
            phx-debounce="300"
            autocomplete="off"
            spellcheck="false"
            maxlength="200"
          />
        </label>
        <div class="search-filters">
          <label>
            <span class="visually-hidden">{gettext("Content type")}</span>
            <select id="search-type" name="type" class="admin-select">
              <option value="">{type_option(gettext("All content types"), facet_total(@results.facets), @filters.q)}</option>
              <option :for={type <- @types} value={type.key} selected={@filters.type == type.key}>
                {type_option(type.label, Map.get(@results.facets, type.key, 0), @filters.q)}
              </option>
            </select>
          </label>
          <label :if={length(@languages) > 1}>
            <span class="visually-hidden">{gettext("Language")}</span>
            <select id="search-language" name="language" class="admin-select">
              <option value="">{gettext("All languages")}</option>
              <option :for={{code, name} <- @languages} value={code} selected={@filters.language == code}>{name}</option>
            </select>
          </label>
          <label>
            <span class="visually-hidden">{gettext("Status")}</span>
            <select id="search-status" name="status" class="admin-select">
              <option value="">{gettext("Any status")}</option>
              <option :for={{status, label} <- @statuses} value={status} selected={@filters.status == status}>
                {label}
              </option>
            </select>
          </label>
          <label>
            <span class="visually-hidden">{gettext("Sort by")}</span>
            <select id="search-sort" name="sort" class="admin-select">
              <option :for={{sort, label} <- @sorts} value={sort} selected={@filters.sort == sort}>{label}</option>
            </select>
          </label>
        </div>
      </form>

      <section class="search-results" aria-labelledby="search-results-count">
        <%= cond do %>
          <% @filters.q == "" -> %>
            <div class="search-empty" id="search-start">
              <h2>{gettext("Search all content")}</h2>
              <p>{gettext("Type a word or a phrase. Put a phrase in quotes, or a minus before a word to leave it out.")}</p>
            </div>
          <% @results[:unavailable] -> %>
            <div class="search-empty" id="search-unavailable">
              <h2>{gettext("Search is not set up here")}</h2>
              <p>{gettext("The search index needs its migration. Ask an administrator to run it.")}</p>
            </div>
          <% @results.total == 0 -> %>
            <div class="search-empty" id="search-none" role="status">
              <h2>{gettext("Nothing matches “%{query}”", query: @filters.q)}</h2>
              <p>{gettext("Check the spelling, try fewer words, or clear the filters.")}</p>
            </div>
          <% true -> %>
            <ol class="search-list" id="search-list">
              <li :for={row <- @results.rows} id={row.id} class="search-row" data-status={row.status}>
                <.result row={row} />
              </li>
            </ol>
            <footer class="search-footer">
              <span id="search-results-count" class="search-count" role="status">
                {ngettext("%{count} result", "%{count} results", @results.total)}
              </span>
              <nav :if={@total_pages > 1} class="search-pages" aria-label={gettext("Pages")}>
                <.link
                  :if={@filters.page > 1}
                  patch={page_path(@filters, @filters.page - 1)}
                  class="search-page-step"
                  aria-label={gettext("Previous page")}
                  rel="prev"
                >
                  <.icon name="chevron-left" />
                </.link>
                <%= for {page, index} <- Enum.with_index(ContentList.page_window(@filters.page, @total_pages)) do %>
                  <span :if={page == :gap} :key={"gap-#{index}"} class="search-page-gap" aria-hidden="true">…</span>
                  <.link
                    :if={page != :gap}
                    :key={page}
                    patch={page_path(@filters, page)}
                    class="search-page"
                    aria-current={page == @filters.page && "page"}
                  >
                    {page}
                  </.link>
                <% end %>
                <.link
                  :if={@filters.page < @total_pages}
                  patch={page_path(@filters, @filters.page + 1)}
                  class="search-page-step"
                  aria-label={gettext("Next page")}
                  rel="next"
                >
                  <.icon name="chevron-right" />
                </.link>
              </nav>
            </footer>
        <% end %>
      </section>
    </div>
    """
  end

  attr :row, :map, required: true

  # The identifier row of the palette and the listings: cover, title, type
  # and language, the status on the right, and the snippet under them. A row
  # the user may not edit is not a link.
  defp result(%{row: %{url: url}} = assigns) when is_binary(url) do
    ~H"""
    <.link navigate={@row.url} class="search-row-body">
      <.result_content row={@row} />
    </.link>
    """
  end

  defp result(assigns) do
    ~H"""
    <div class="search-row-body">
      <.result_content row={@row} />
    </div>
    """
  end

  attr :row, :map, required: true

  # The snippet is escaped text; only its marks are markup.
  defp result_content(assigns) do
    ~H"""
    <span class="search-cover">
      <img :if={is_binary(@row.cover) and @row.cover != ""} src={@row.cover} alt="" loading="lazy" />
      <.icon :if={!is_binary(@row.cover) or @row.cover == ""} name={@row.icon} />
    </span>
    <span class="search-copy">
      <span class="search-title-line">
        <span class="search-title">{@row.title}</span>
        <span class="search-meta"><span>{@row.type}</span><span :if={@row.language}>{@row.language}</span></span>
      </span>
      <span :if={@row.snippet != []} class="search-snippet"><%= for {kind, text} <- @row.snippet do %>
        <mark :if={kind == :mark}>{text}</mark><span :if={kind == :text}>{text}</span>
      <% end %></span>
    </span>
    <span class="search-status" data-status={@row.status}>
      <i aria-hidden="true"></i><span>{status_label(@row.status)}</span>
    </span>
    """
  end

  defp facet_total(facets), do: facets |> Map.values() |> Enum.sum()

  defp type_option(label, _count, ""), do: label
  defp type_option(label, count, _q), do: "#{label} (#{count})"

  defp status_label(status) when status in [:published, "published"], do: gettext("Published")
  defp status_label(status) when status in [:draft, "draft"], do: gettext("Draft")
  defp status_label(status) when status in [:pending, "pending"], do: gettext("Pending")
  defp status_label(status) when status in [:disabled, "disabled"], do: gettext("Disabled")
  defp status_label(_), do: gettext("Not set")
end
