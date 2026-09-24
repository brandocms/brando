defmodule BrandoAdmin.Images.AltTextLive do
  @moduledoc """
  Images → Alt text: images in the library without alt text, what describing
  them with AI would cost, and the review list for what it wrote.

  Nothing is saved until a suggestion is accepted (`Brando.SEO.Suggestions`).
  The text goes on the image asset, in the site's default language.
  """
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.AI
  alias Brando.Images.AltText
  alias Brando.Images.Image
  alias Brando.SEO.Suggestions
  alias BrandoAdmin.Components.SuggestionReview
  alias BrandoAdmin.Components.Workspace

  @fields [:alt]

  # The admin layout renders nothing until the socket connects, so the
  # queries wait for that.
  def mount(_params, %{"user_token" => token}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Suggestions.topic())
      {:ok, socket |> assign(:socket_connected, true) |> assign_page(token)}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  defp assign_page(socket, token) do
    socket
    |> assign_new(:current_user, fn -> Brando.Users.get_user_by_session_token(token) end)
    |> set_admin_locale()
    |> assign(:language, to_string(Brando.config(:default_language)))
    |> assign(:ai_available, AI.configured?(AltText.ai_opts()))
    |> assign(:folder_id, nil)
    |> assign(:accepting_all, false)
    |> assign(:max_batch, Suggestions.max_batch())
    |> assign_state()
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace alt-text-workspace">
      <Workspace.header
        title={gettext("Alt text")}
        subtitle={
          gettext(
            "Alt text describes an image to people who cannot see it, and to search engines. It is written on the image and used wherever the image appears, unless a placement overrides it."
          )
        }
      >
        <.link navigate={Brando.routes().admin_live_path(@socket, BrandoAdmin.Images.ImageListLive)} class="workspace-button">
          {gettext("Back to images")}
        </.link>
      </Workspace.header>

      <section class="workspace-panel alt-text-panel">
        <header class="workspace-panel-heading">
          <div>
            <h2>{gettext("Images without alt text")}</h2>
            <p>
              {gettext("Text is written in %{language}, the site's default language.",
                language: AI.language_name(@language)
              )}
            </p>
          </div>
          <span>{@missing_count}</span>
        </header>

        <form :if={length(@folders) > 1} class="alt-text-filter" phx-change="folder">
          <label for="alt-text-folder">{gettext("Folder")}</label>
          <select id="alt-text-folder" name="folder_id" class="admin-select">
            <option value="" selected={is_nil(@folder_id)}>{gettext("All folders")}</option>
            <option :for={{id, name, count} <- @folders} :if={id} value={id} selected={@folder_id == id}>
              {name} ({count})
            </option>
          </select>
        </form>

        <div class="alt-text-body">
          <BrandoAdmin.Components.Workspace.empty
            :if={@candidates == [] and @missing_count == 0}
            title={gettext("Every image has alt text")}
            description={gettext("New uploads without alt text will be listed here.")}
          />

          <p :if={@candidates == [] and @missing_count > 0}>
            {gettext("Every image without alt text already has a suggestion below.")}
          </p>

          <p :if={!@ai_available and @candidates != []}>
            {gettext(
              "Connect an AI provider to write alt text from the images themselves, or add it on each image in the library."
            )}
          </p>

          <div :if={@ai_available and @candidates != []} class="alt-text-estimate">
            <.estimate estimate={@estimate} count={min(length(@candidates), @max_batch)} />
            <p :if={length(@candidates) > @max_batch} class="alt-text-note">
              {gettext("At most %{max} per run; run it again for the rest.", max: @max_batch)}
            </p>
            <div class="alt-text-actions">
              <button
                type="button"
                class="workspace-button primary"
                phx-click="describe"
                disabled={match?({:error, :no_image_input}, @estimate)}
              >
                {ngettext("Describe one image", "Describe %{count} images", min(length(@candidates), @max_batch))}
              </button>
            </div>
          </div>
        </div>

        <SuggestionReview.review
          :if={@suggestions != []}
          id="alt-text-suggestions"
          heading={gettext("Suggested alt text")}
          suggestions={@suggestions}
          accepting_all={@accepting_all}
          thumbnail={&Map.get(@thumbnails, &1.entry_id)}
          label={&gettext("Suggested alt text for %{title}", title: &1.title)}
        />
      </section>
    </div>
    """
  end

  attr :estimate, :any
  attr :count, :integer

  defp estimate(assigns) do
    ~H"""
    <%= case @estimate do %>
      <% {:ok, estimate} -> %>
        <p>
          {ngettext(
            "Describing one image with %{model} costs about %{total}.",
            "Describing %{count} images with %{model} costs about %{total} — roughly %{each} per image.",
            @count,
            model: estimate.spec,
            total: Brando.AI.Cost.format(estimate.total),
            each: Brando.AI.Cost.format(estimate.per_image)
          )}
        </p>
        <p class="alt-text-note">
          {gettext(
            "An estimate from the model's published prices and each image's size; your provider bills what is actually used. The images are sent to the provider."
          )}
        </p>
      <% {:error, :no_image_input} -> %>
        <p class="error">
          {gettext("The configured AI model cannot read images. Configure one that can for the alt field.")}
        </p>
      <% _ -> %>
        <p>
          {gettext(
            "No price is known for the configured AI model. Check your provider's pricing before describing many images."
          )}
        </p>
    <% end %>
    """
  end

  def handle_event("folder", %{"folder_id" => folder_id}, socket) do
    folder_id =
      case Integer.parse(folder_id) do
        {id, ""} -> id
        _ -> nil
      end

    {:noreply, socket |> assign(:folder_id, folder_id) |> assign_state()}
  end

  def handle_event("describe", _params, socket) do
    %{candidates: candidates, language: language, current_user: user, ai_available: available?} = socket.assigns

    if available? and candidates != [] do
      rows = Enum.map(candidates, &%{schema: Image, id: &1.id, title: image_title(&1)})
      {:ok, count} = Suggestions.enqueue(rows, language, user, field: :alt)
      send(self(), {:toast, ngettext("Describing one image", "Describing %{count} images", count)})
      {:noreply, assign_state(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("accept_suggestion", %{"suggestion_id" => id} = params, socket) do
    case Suggestions.accept(id, params["text"], socket.assigns.current_user) do
      {:ok, _suggestion} ->
        send(self(), {:toast, gettext("Alt text saved")})

      {:error, :not_found} ->
        send(self(), {:toast, gettext("This suggestion was already reviewed")})

      {:error, :empty} ->
        send(self(), {:toast, gettext("Write the alt text before accepting it")})

      {:error, _} ->
        send(self(), {:toast, gettext("Could not save the alt text")})
    end

    {:noreply, assign_state(socket)}
  end

  def handle_event("reject_suggestion", %{"id" => id}, socket) do
    Suggestions.reject(id, socket.assigns.current_user)
    {:noreply, assign_state(socket)}
  end

  def handle_event("accept_all_suggestions", _params, socket) do
    %{language: language, current_user: user} = socket.assigns
    run = Brando.Tenant.capture_context(fn -> Suggestions.accept_all(language, user, @fields) end)
    {:noreply, socket |> assign(:accepting_all, true) |> start_async(:accept_all, run)}
  end

  def handle_async(:accept_all, result, socket) do
    case result do
      {:ok, {accepted, 0}} ->
        send(self(), {:toast, ngettext("One alt text saved", "%{count} alt texts saved", accepted)})

      {:ok, {accepted, failed}} ->
        send(
          self(),
          {:toast, gettext("%{accepted} saved, %{failed} could not be saved", accepted: accepted, failed: failed)}
        )

      {:exit, _reason} ->
        send(self(), {:toast, gettext("Could not save the alt text")})
    end

    {:noreply, socket |> assign(:accepting_all, false) |> assign_state()}
  end

  def handle_info({:seo_suggestions_updated, language}, socket) do
    if language == socket.assigns.language, do: {:noreply, assign_state(socket)}, else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Images without alt text, less those a suggestion is on its way for or
  # waiting on review, and what describing them would cost.
  defp assign_state(socket) do
    %{language: language, folder_id: folder_id, max_batch: max_batch} = socket.assigns
    suggestions = Suggestions.list_open(language, @fields)
    waiting = MapSet.new(suggestions, & &1.entry_id)
    missing = AltText.missing()
    in_folder = if folder_id, do: Enum.filter(missing, &(&1.folder_id == folder_id)), else: missing
    candidates = Enum.reject(in_folder, &MapSet.member?(waiting, &1.id))

    estimate =
      if socket.assigns.ai_available and candidates != [],
        do: AltText.estimate(Enum.take(candidates, max_batch))

    socket
    |> assign(:missing_count, length(in_folder))
    |> assign(:candidates, candidates)
    |> assign(:estimate, estimate)
    |> assign(:folders, folders(missing))
    |> assign(:suggestions, suggestions)
    |> assign(:thumbnails, thumbnails(suggestions))
  end

  defp folders(missing) do
    counts = Enum.frequencies_by(missing, & &1.folder_id)
    ids = counts |> Map.keys() |> Enum.reject(&is_nil/1)

    names =
      Brando.Repo.all(from(f in Brando.Media.Folder, where: f.id in ^ids, select: {f.id, f.name, f.path}))
      |> Map.new(fn {id, name, path} -> {id, name || path} end)

    counts
    |> Enum.map(fn {id, count} -> {id, Map.get(names, id, gettext("Root folder")), count} end)
    |> Enum.sort_by(&elem(&1, 1))
  end

  defp thumbnails([]), do: %{}

  defp thumbnails(suggestions) do
    ids = Enum.map(suggestions, & &1.entry_id)

    from(i in Image, where: i.id in ^ids)
    |> Brando.Repo.all()
    |> Map.new(fn image -> {image.id, thumbnail_url(image)} end)
  end

  defp thumbnail_url(image) do
    size = if Map.has_key?(image.sizes || %{}, "thumb"), do: :thumb, else: :original
    Brando.Utils.img_url(image, size, prefix: Brando.Utils.media_url())
  rescue
    _ -> nil
  end

  defp image_title(image) do
    case image.title do
      title when is_binary(title) and title != "" -> title
      _ -> Path.basename(image.path)
    end
  end
end
