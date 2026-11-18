defmodule BrandoAdmin.Components.Assets.ProviderLibraryPanel do
  @moduledoc """
  "Add from <provider>": browse a video provider's own library and add its
  videos to Brando's (`Brando.Videos.ProviderLibrary`). Shared by the video
  picker and the Videos library.

  The state is two of the owner's assigns: `:library_providers`, the
  providers it offers (`providers/2`), and `:library`, the one open, or nil.
  The owner handles the panel's events and hands them on:

    * `open_library` (from its own button): `open/2`
    * `close_library`: assign `:library` nil
    * `search_library`: `search/2`
    * `more_library`: `more/1`
    * `add_from_library`: `add/4`, which creates the record, or returns the
      one that already holds the video
    * `handle_async(:library_page, result, socket)`: `page_loaded/2`

  A page is listed off the LiveView process; adding is synchronous, as it
  creates a record under the editor's authorization and tenant context,
  which an async task would not carry.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Phoenix.LiveView, only: [start_async: 3]

  alias Brando.Videos.ProviderLibrary

  @doc """
  The provider libraries `user` can add from. Adding an existing provider
  video is linking an external video, so it follows the config's
  `allow_external_urls`.
  """
  def providers(user, allow_external_urls?) do
    with true <- allow_external_urls?,
         :ok <- Brando.Authorization.Media.authorize(user, :video) do
      ProviderLibrary.providers()
    else
      _ -> []
    end
  end

  @doc "Opens the library of `strategy`, one of `:library_providers`, at its first page."
  def open(socket, strategy) do
    case Enum.find(socket.assigns.library_providers, &(Atom.to_string(&1.strategy) == to_string(strategy))) do
      nil ->
        :error

      provider ->
        library = %{
          strategy: provider.strategy,
          label: provider.label,
          search?: provider.search?,
          query: "",
          items: [],
          next: nil,
          loading?: false,
          error: nil,
          ref: nil
        }

        {:ok, socket |> assign(:library, library) |> load_page(nil)}
    end
  end

  @doc "Lists the open library's videos matching `query`."
  def search(%{assigns: %{library: %{} = library}} = socket, query) do
    socket
    |> assign(:library, %{library | query: String.trim(query), items: [], next: nil})
    |> load_page(nil)
  end

  def search(socket, _query), do: socket

  @doc "Lists the open library's next page."
  def more(%{assigns: %{library: %{next: next}}} = socket) when not is_nil(next), do: load_page(socket, next)
  def more(socket), do: socket

  @doc "A page listed, from the owner's `handle_async(:library_page, result, socket)`."
  def page_loaded(socket, {:ok, {ref, cursor, result}}) do
    case socket.assigns.library do
      %{ref: ^ref} = library -> assign(socket, :library, apply_page(library, cursor, result))
      # Closed, or superseded by a newer search.
      _ -> socket
    end
  end

  def page_loaded(%{assigns: %{library: %{} = library}} = socket, {:exit, _reason}) do
    assign(socket, :library, %{library | loading?: false, error: error_message(:provider_error, library.label)})
  end

  def page_loaded(socket, _result), do: socket

  @doc """
  Adds the open library's video `remote_id` to Brando's library as `user`,
  with `opts` for `Brando.Videos.ProviderLibrary.import/4`. A video Brando
  holds already comes back as it is. Its row is marked as in the library.

  `{:ok, video, socket}`, or `{:error, socket}` with the error on the panel.
  """
  def add(%{assigns: %{library: %{} = library}} = socket, remote_id, user, opts) do
    case ProviderLibrary.import(library.strategy, remote_id, user, opts) do
      {:ok, video} ->
        items =
          Enum.map(library.items, fn
            %{remote_id: ^remote_id} = item -> %{item | video_id: video.id}
            item -> item
          end)

        {:ok, video, assign(socket, :library, %{library | items: items, error: nil})}

      {:error, reason} ->
        {:error, assign(socket, :library, %{library | error: error_message(reason, library.label)})}
    end
  end

  def add(socket, _remote_id, _user, _opts), do: {:error, socket}

  defp apply_page(library, cursor, {:ok, %{items: items, next: next}}) do
    items = if cursor, do: library.items ++ items, else: items
    %{library | items: items, next: next, loading?: false}
  end

  defp apply_page(library, _cursor, {:error, reason}),
    do: %{library | loading?: false, error: error_message(reason, library.label)}

  defp load_page(socket, cursor) do
    library = socket.assigns.library
    ref = make_ref()
    strategy = library.strategy
    opts = [cursor: cursor, query: library.query]

    socket
    |> assign(:library, %{library | loading?: true, error: nil, ref: ref})
    |> start_async(
      :library_page,
      Brando.Tenant.capture_context(fn -> {ref, cursor, ProviderLibrary.list(strategy, opts)} end)
    )
  end

  @doc "What the editor is told when the provider `provider` (its label) refuses or fails."
  def error_message(:signed_playback_not_supported, _provider),
    do: gettext("This video needs signed playback, which Brando does not support.")

  def error_message(:holdings_unavailable, _provider),
    do: gettext("Could not check which sites use these videos. Try again in a moment.")

  def error_message(:busy, _provider),
    do: gettext("This video is being added or deleted elsewhere. Try again in a moment.")

  def error_message(:not_found, provider), do: gettext("%{provider} no longer has this video.", provider: provider)

  def error_message(reason, _provider) when is_binary(reason), do: reason

  def error_message(_reason, provider),
    do: gettext("Could not reach %{provider}. Try again in a moment.", provider: provider)

  @doc """
  A row's details: its duration, size and the day it was added, as in
  "0:30 · 1280 × 720 · 2026-09-01".
  """
  def item_meta(item) do
    [
      duration(item.duration),
      item.width && item.height && "#{item.width} × #{item.height}",
      is_binary(item.created_at) && String.slice(item.created_at, 0, 10)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp duration(seconds) when is_number(seconds) and seconds > 0 do
    total = round(seconds)
    minutes = div(total, 60)
    "#{minutes}:#{total |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp duration(_seconds), do: nil

  defp status(%{status: :processing}), do: gettext("Processing")
  defp status(%{status: :errored}), do: gettext("Failed")
  defp status(_item), do: gettext("Signed playback")

  attr :id, :string, required: true, doc: "the owner's id; the panel is `\#{id}-library`"
  attr :library, :map, required: true
  attr :target, :any, default: nil, doc: "the component handling the events; without one, the LiveView"

  attr :heading, :boolean,
    default: true,
    doc: "the panel's own heading and close button; false inside a modal, which has both"

  attr :select_existing, :boolean,
    default: true,
    doc: "a video Brando holds already can be selected; false where there is nothing to select for"

  @doc "The open library: its search, its videos and an Add for each."
  def panel(assigns) do
    ~H"""
    <section
      id={"#{@id}-library"}
      class="video-picker-library"
      aria-label={gettext("%{provider} library", provider: @library.label)}
    >
      <div :if={@heading} class="video-picker-library-header">
        <div>
          <h4>{gettext("%{provider} library", provider: @library.label)}</h4>
          <p>{description(@library.label)}</p>
        </div>
        <button
          type="button"
          class="video-picker-library-close"
          aria-label={gettext("Close")}
          phx-click="close_library"
          phx-target={@target}
        >
          <.icon name="x" />
        </button>
      </div>
      <p :if={!@heading} class="video-picker-library-lede">{description(@library.label)}</p>

      <form
        :if={@library.search?}
        class="video-picker-library-search"
        phx-submit="search_library"
        phx-target={@target}
      >
        <input
          id={"#{@id}-library-query"}
          type="search"
          name="query"
          class="text"
          value={@library.query}
          aria-label={gettext("Search %{provider}", provider: @library.label)}
          placeholder={gettext("Search %{provider} by title", provider: @library.label)}
        />
        <button type="submit" class="btn">{gettext("Search")}</button>
      </form>

      <p :if={@library.error} class="video-picker-library-error" role="alert">{@library.error}</p>

      <ul :if={@library.items != []} class="video-picker-library-items">
        <li :for={item <- @library.items} class="video-picker-library-item" data-remote-id={item.remote_id}>
          <div class="video-picker-library-thumb">
            <img :if={item.thumbnail_url} src={item.thumbnail_url} alt="" loading="lazy" />
            <.icon :if={!item.thumbnail_url} name="film" />
          </div>
          <div class="video-picker-library-info">
            <span class="video-picker-library-title">{item.title || gettext("Untitled video")}</span>
            <span class="video-picker-library-meta">{item_meta(item)}</span>
          </div>
          <div class="video-picker-library-action">
            <%= cond do %>
              <% item.video_id -> %>
                <span class="video-picker-library-status">{gettext("In library")}</span>
                <button
                  :if={@select_existing}
                  type="button"
                  class="btn btn--sm"
                  phx-click="add_from_library"
                  phx-value-remote-id={item.remote_id}
                  phx-target={@target}
                >
                  {gettext("Select")}
                </button>
              <% item.playable? -> %>
                <button
                  type="button"
                  class="btn btn--sm"
                  phx-click="add_from_library"
                  phx-value-remote-id={item.remote_id}
                  phx-target={@target}
                  phx-disable-with={gettext("Adding…")}
                >
                  {gettext("Add")}
                </button>
              <% true -> %>
                <span class="video-picker-library-status">{status(item)}</span>
            <% end %>
          </div>
        </li>
      </ul>

      <p :if={@library.loading?} class="video-picker-library-note" role="status">
        {gettext("Loading videos…")}
      </p>
      <p
        :if={!@library.loading? && !@library.error && @library.items == []}
        class="video-picker-library-note"
      >
        <%= if @library.query != "" do %>
          {gettext("No videos match “%{query}”.", query: @library.query)}
        <% else %>
          {gettext("No videos in this %{provider} account.", provider: @library.label)}
        <% end %>
      </p>
      <button
        :if={@library.next && !@library.loading?}
        type="button"
        class="image-picker-more"
        phx-click="more_library"
        phx-target={@target}
      >
        {gettext("Load more")}
      </button>
    </section>
    """
  end

  defp description(provider) do
    gettext(
      "Videos already in your %{provider} account. Deleting one here later leaves it in %{provider}.",
      provider: provider
    )
  end
end
