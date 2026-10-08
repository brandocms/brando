defmodule BrandoAdmin.Components.Form.MetaPreviews do
  @moduledoc """
  The Previews tab of an entry's Meta drawer: the search result, the Open
  Graph card (Facebook, LinkedIn) and the X card the page gives, and its
  Markdown version.

  The cards follow the form as it is edited (`Brando.SEO.SharePreview`); the
  image is the one `render_meta` shares, in the size it shares, with a marker
  where its focal point lands. The address and the Markdown are read from the
  saved entry on `load`, sent when the tab opens, so opening the entry costs
  nothing.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.SEO.Markdown
  alias Brando.SEO.SharePreview
  alias Ecto.Changeset

  @excerpt_lines 14
  @excerpt_chars 900

  # prop form, :form, required: true
  # prop schema, :atom, required: true
  # prop entry_id, :any

  def mount(socket) do
    {:ok, assign(socket, loaded: nil, images: %{})}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    entry = Changeset.apply_changes(socket.assigns.form.source)
    {image, socket} = current_meta_image(entry, socket)
    entry = if Map.has_key?(entry, :meta_image), do: %{entry | meta_image: image}, else: entry
    language = to_string(Map.get(entry, :language) || Brando.config(:default_language))

    {:ok, assign(socket, :values, SharePreview.values(socket.assigns.schema, entry, language))}
  end

  # The form holds the picked image's id; the struct beside it can be the one
  # the entry was loaded with. Load a newly picked one once.
  defp current_meta_image(%{meta_image_id: id} = entry, socket) when not is_nil(id) do
    case Map.get(entry, :meta_image) do
      %Brando.Images.Image{id: ^id} = image ->
        {image, socket}

      _ ->
        case Map.fetch(socket.assigns.images, id) do
          {:ok, image} ->
            {image, socket}

          :error ->
            image =
              case Brando.Images.get_image(id) do
                {:ok, image} -> image
                _ -> nil
              end

            {image, update(socket, :images, &Map.put(&1, id, image))}
        end
    end
  end

  defp current_meta_image(_entry, socket), do: {nil, socket}

  def handle_event("load", _params, %{assigns: %{entry_id: nil}} = socket), do: {:noreply, socket}

  def handle_event("load", _params, socket) do
    %{schema: schema, entry_id: entry_id} = socket.assigns

    case Brando.Blueprint.EntryQuery.get(schema, entry_id) do
      {:ok, entry} -> {:noreply, assign(socket, :loaded, loaded(schema, entry))}
      {:error, _} -> {:noreply, assign(socket, :loaded, :error)}
    end
  end

  defp loaded(schema, entry) do
    url = Brando.Blueprint.URL.resolve(entry, :with_host)
    markdown? = Markdown.enabled?(schema) and is_binary(url)

    %{
      url: url,
      markdown_enabled?: Markdown.enabled?(schema),
      markdown_url: markdown? && Markdown.url(entry),
      markdown_served?: markdown? && Markdown.available?(entry),
      markdown: markdown? && excerpt(Markdown.render(entry))
    }
  end

  defp excerpt(markdown) do
    lines = String.split(String.trim(markdown), "\n")
    text = lines |> Enum.take(@excerpt_lines) |> Enum.join("\n")

    if length(lines) > @excerpt_lines or String.length(text) > @excerpt_chars,
      do: {String.slice(text, 0, @excerpt_chars), true},
      else: {text, false}
  end

  def render(assigns) do
    host = URI.parse(Brando.Utils.hostname()).host

    assigns =
      assigns
      |> assign(:host, host)
      |> assign(:crumbs, crumbs(assigns.loaded, host))
      |> assign(:open_graph, SharePreview.frame(assigns.values.image, :open_graph))
      |> assign(:x, SharePreview.frame(assigns.values.image, :x))
      |> assign(:image_source, image_source(assigns))

    ~H"""
    <div id={@id} class="meta-previews">
      <%!-- Two columns that stack independently: the short search result
            and the Markdown at the left, the two share cards at the right. --%>
      <div class="meta-previews-grid">
        <div class="meta-previews-column">
          <section class="meta-preview-card meta-preview-search" data-testid="meta-preview-search">
            <h4 class="meta-preview-label"><.icon name="search" />{gettext("Search result")}</h4>
            <div class="meta-preview-site">
              <span class="meta-preview-favicon" aria-hidden="true"></span>
              <span>{@crumbs}</span>
            </div>
            <p class="meta-preview-search-title">
              {SharePreview.truncate(@values.search_title, :title) || gettext("No title")}
            </p>
            <p class="meta-preview-search-description">
              {SharePreview.truncate(@values.description, :description) ||
                gettext("No description. Search engines pick text from the page.")}
            </p>
          </section>

          <section class="meta-preview-markdown" data-testid="meta-preview-markdown">
            <.markdown loaded={@loaded} entry_id={@entry_id} />
          </section>
        </div>

        <div class="meta-previews-column">
          <section class="meta-preview-card meta-preview-og" data-testid="meta-preview-open-graph">
            <h4 class="meta-preview-label"><.icon name="share-2" />{gettext("Facebook, LinkedIn")}</h4>
            <.share_image frame={@open_graph} kind="og" />
            <div class="meta-preview-og-text">
              <span>{@host}</span>
              <strong>{@values.title || gettext("No title")}</strong>
            </div>
          </section>

          <section class="meta-preview-card meta-preview-x" data-testid="meta-preview-x">
            <h4 class="meta-preview-label"><.icon name="at-sign" />{gettext("X")}</h4>
            <div class="meta-preview-x-media">
              <.share_image frame={@x} kind="x" />
              <span class="meta-preview-x-host">{@host}</span>
            </div>
            <p class="meta-preview-x-title">{@values.title || gettext("No title")}</p>
          </section>
        </div>
      </div>

      <p class="meta-preview-note">
        {@image_source}
        <span :if={@open_graph && @open_graph.focal}>{gettext("The ring marks its focal point.")}</span>
      </p>
    </div>
    """
  end

  attr :frame, :any, required: true
  attr :kind, :string, required: true

  # The shared file, cut to the card's shape the way the platform cuts it,
  # with a ring where the focal point lands. Positioned with SVG attributes,
  # not inline styles.
  defp share_image(assigns) do
    ~H"""
    <div class={["meta-preview-image", "meta-preview-image--#{@kind}"]} data-cropped={@frame && to_string(@frame.cropped?)}>
      <%= if @frame do %>
        <img src={@frame.src} alt="" loading="lazy" />
        <svg :if={@frame.focal} class="meta-preview-focal" aria-hidden="true">
          <svg x={"#{elem(@frame.focal, 0)}%"} y={"#{elem(@frame.focal, 1)}%"} overflow="visible">
            <circle r="9" />
          </svg>
        </svg>
      <% else %>
        <span class="meta-preview-no-image">{gettext("No image")}</span>
      <% end %>
    </div>
    """
  end

  attr :loaded, :any, required: true
  attr :entry_id, :any, required: true

  defp markdown(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@entry_id) -> %>
        <h4 class="meta-preview-label">{gettext("Markdown version")}</h4>
        <p class="meta-preview-empty">{gettext("Save the entry to see its Markdown version.")}</p>
      <% is_nil(@loaded) -> %>
        <h4 class="meta-preview-label">{gettext("Markdown version")}</h4>
        <p class="meta-preview-empty" role="status">{gettext("Reading the entry…")}</p>
      <% @loaded == :error -> %>
        <h4 class="meta-preview-label">{gettext("Markdown version")}</h4>
        <p class="meta-preview-empty">{gettext("The entry could not be read.")}</p>
      <% !@loaded.markdown_enabled? -> %>
        <h4 class="meta-preview-label">{gettext("Markdown version")}</h4>
        <p class="meta-preview-empty">{gettext("This content type has no Markdown version.")}</p>
      <% !@loaded.markdown_url -> %>
        <h4 class="meta-preview-label">{gettext("Markdown version")}</h4>
        <p class="meta-preview-empty">{gettext("This entry has no address of its own, so no Markdown version.")}</p>
      <% true -> %>
        <h4 class="meta-preview-label">
          {gettext("Markdown version")} ·
          <a class="meta-preview-markdown-path" href={@loaded.markdown_url} target="_blank" rel="noopener">
            {URI.parse(@loaded.markdown_url).path}
          </a>
        </h4>
        <pre class="meta-preview-markdown-text" data-truncated={to_string(elem(@loaded.markdown, 1))}>{elem(@loaded.markdown, 0)}</pre>
        <p :if={!@loaded.markdown_served?} class="meta-preview-empty">
          {gettext("Served once the entry is published. This is the last saved version.")}
        </p>
    <% end %>
    """
  end

  defp crumbs(%{url: url}, host) when is_binary(url) do
    segments = url |> URI.parse() |> Map.get(:path) |> to_string() |> String.split("/", trim: true)
    Enum.join([host | segments], " › ")
  end

  defp crumbs(_loaded, host), do: host

  defp image_source(%{values: %{image: nil}}),
    do: gettext("No sharing image. Platforms show a small card without one.")

  defp image_source(%{values: %{image: image}, form: form}) do
    meta_image_id = form.source |> Changeset.get_field(:meta_image_id, nil)

    cond do
      match?(%Brando.Images.Image{id: id} when id == meta_image_id and not is_nil(id), image) ->
        gettext("The meta image, as it is shared.")

      fallback_image?(image, form) ->
        gettext("The fallback image from the SEO settings, as it is shared.")

      true ->
        gettext("The image this content type shares, as it is shared.")
    end
  end

  defp fallback_image?(%Brando.Images.Image{id: id}, form) do
    language = to_string(Changeset.get_field(form.source, :language, nil) || Brando.config(:default_language))

    case Brando.Cache.SEO.get(language).fallback_meta_image do
      %Brando.Images.Image{id: ^id} -> true
      _ -> false
    end
  end

  defp fallback_image?(_image, _form), do: false
end
