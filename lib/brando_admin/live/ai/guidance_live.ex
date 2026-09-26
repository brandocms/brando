defmodule BrandoAdmin.AI.GuidanceLive do
  @moduledoc """
  Configuration → Assistant: the guidance the content assistant follows in
  this site/environment, beside the developers' guidance from the code.

  Only users who may configure the assistant see it (superusers, unless a
  group is granted `brando.assistant.configure`). Every save is a version;
  earlier versions, and the guidance of other sites and environments the user
  may configure, can be loaded into the editor and saved from there.
  """
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.AI.Agent.Guidance

  @max_length 12_000

  def __authorization__, do: {:configure, :assistant}

  def mount(_params, %{"user_token" => token}, socket) do
    socket = BrandoAdmin.Hooks.assign_current_user(socket, token)
    user = socket.assigns.current_user
    Gettext.put_locale(Brando.Gettext, to_string(user.language))

    if Guidance.configurable?(user) do
      current = Guidance.current()

      {:ok,
       socket
       |> assign(
         socket_connected: connected?(socket),
         scope_label: Guidance.label(),
         current: current,
         draft: (current && current.text) || "",
         note: nil,
         code: Guidance.code_guidance(),
         sources: Guidance.sources(user),
         max_length: @max_length
       )
       |> assign_history()}
    else
      {:ok, redirect(socket, to: "/admin")}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        dirty?: assigns.draft != ((assigns.current && assigns.current.text) || ""),
        length: String.length(assigns.draft)
      )

    ~H"""
    <div class="guidance-workspace">
      <header class="guidance-heading">
        <div>
          <span class="guidance-eyebrow">{gettext("Configuration")}</span>
          <h1>{gettext("Assistant guidance")}</h1>
          <p>{gettext("The conventions the content assistant follows when it builds content for editors.")}</p>
        </div>
        <span class="guidance-scope"><.icon name="hero-globe-alt" />{@scope_label}</span>
      </header>

      <section class="guidance-card" aria-labelledby="guidance-editor-title">
        <div class="guidance-card-heading">
          <h2 id="guidance-editor-title">{gettext("Guidance for %{scope}", scope: @scope_label)}</h2>
          <p>
            {gettext(
              "Name modules, slots and settings the way editors see them, for example: Start an article with the Article lede module. The assistant asks when a name does not match. Editors can read this guidance in the assistant, and their own requests take precedence. Permissions and review still apply."
            )}
          </p>
        </div>

        <form id="guidance-form" phx-change="draft" phx-submit="save">
          <label for="guidance-text">{gettext("Guidance")}</label>
          <textarea
            id="guidance-text"
            name="text"
            rows="14"
            maxlength={@max_length}
            phx-debounce="300"
            placeholder={gettext("For example: Portrait image pairs use the Two images module with the narrow setting on.")}
          >{@draft}</textarea>

          <div class="guidance-form-footer">
            <div class="guidance-form-status">
              <span class={["guidance-count", @length > @max_length && "is-over"]}>
                {gettext("%{count} of %{max} characters", count: @length, max: @max_length)}
              </span>
              <span :if={@note && @dirty?} class="guidance-note">{@note}</span>
              <span :if={!@dirty? && @current} class="guidance-saved">
                {gettext("Saved %{time} by %{author}", time: timestamp(@current.inserted_at), author: author(@current))}
              </span>
            </div>
            <div class="guidance-actions">
              <button :if={@dirty?} type="button" class="guidance-button quiet" phx-click="discard">
                {gettext("Discard changes")}
              </button>
              <button type="submit" class="guidance-button primary" disabled={!@dirty?} phx-disable-with={gettext("Saving…")}>
                {gettext("Save guidance")}
              </button>
            </div>
          </div>
        </form>

        <form :if={@sources != []} id="guidance-copy" class="guidance-copy" phx-submit="copy">
          <label for="guidance-source">{gettext("Copy from another site or environment")}</label>
          <div class="guidance-copy-row">
            <select id="guidance-source" name="source" class="admin-select">
              <option :for={source <- @sources} value={source.id}>
                {gettext("%{scope} · saved %{time}", scope: source.label, time: timestamp(source.inserted_at))}
              </option>
            </select>
            <button
              type="submit"
              class="guidance-button"
              data-confirm={@dirty? && gettext("Replace your unsaved changes with the copied guidance?")}
            >
              {gettext("Copy into editor")}
            </button>
          </div>
          <p>{gettext("The copy is loaded into the editor. Nothing changes here until you save it.")}</p>
        </form>
      </section>

      <section :if={@code != []} class="guidance-card" aria-labelledby="guidance-code-title">
        <div class="guidance-card-heading">
          <h2 id="guidance-code-title">{gettext("From the site's code")}</h2>
          <p>
            {gettext(
              "Set by the developers in the site's configuration. Where it conflicts with the guidance above, the guidance above applies."
            )}
          </p>
        </div>
        <div :for={{content_type, text} <- @code} class="guidance-code">
          <h3>{if content_type, do: Brando.Blueprint.get_plural(content_type), else: gettext("All content")}</h3>
          <pre>{text}</pre>
        </div>
      </section>

      <section class="guidance-card" aria-labelledby="guidance-history-title">
        <div class="guidance-card-heading">
          <h2 id="guidance-history-title">{gettext("History")}</h2>
        </div>
        <p :if={@history == []} class="guidance-empty">{gettext("No guidance has been saved here yet.")}</p>
        <ol :if={@history != []} class="guidance-history">
          <li :for={version <- @history}>
            <div>
              <strong>{timestamp(version.inserted_at)}</strong>
              <span>{author(version)}</span>
              <span :if={version.note} class="guidance-note">{version.note}</span>
              <p class="guidance-excerpt">{excerpt(version.text)}</p>
            </div>
            <span :if={@current && version.id == @current.id} class="guidance-pill">{gettext("In use")}</span>
            <button
              :if={!(@current && version.id == @current.id)}
              type="button"
              class="guidance-button"
              phx-click="restore"
              phx-value-id={version.id}
              data-confirm={@dirty? && gettext("Replace your unsaved changes with this version?")}
            >
              {gettext("Load into editor")}
            </button>
          </li>
        </ol>
      </section>
    </div>
    """
  end

  def handle_event("draft", %{"text" => text}, socket), do: {:noreply, assign(socket, :draft, text)}

  def handle_event("discard", _, socket),
    do: {:noreply, assign(socket, draft: (socket.assigns.current && socket.assigns.current.text) || "", note: nil)}

  def handle_event("save", %{"text" => text}, socket) do
    case Guidance.save(text, socket.assigns.current_user, note: socket.assigns.note) do
      {:ok, current} ->
        {:noreply,
         socket
         |> assign(current: current, draft: (current && current.text) || "", note: nil)
         |> assign_history()
         |> toast(:info, gettext("Guidance saved"))}

      {:error, message} ->
        {:noreply, toast(socket, :error, message)}
    end
  end

  def handle_event("copy", %{"source" => id}, socket) do
    case Guidance.source(id, socket.assigns.current_user) do
      {:ok, source} ->
        {:noreply, assign(socket, draft: source.text, note: gettext("Copied from %{scope}", scope: source.label))}

      {:error, message} ->
        {:noreply, toast(socket, :error, message)}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.history, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      version ->
        note = gettext("Restored the version from %{time}", time: timestamp(version.inserted_at))
        {:noreply, assign(socket, draft: version.text, note: note)}
    end
  end

  defp assign_history(socket) do
    case Guidance.history(socket.assigns.current_user) do
      {:ok, history} -> assign(socket, :history, history)
      {:error, _} -> assign(socket, :history, [])
    end
  end

  defp toast(socket, level, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{
      level: if(level == :error, do: :error, else: :success),
      type: :notification
    })

    socket
  end

  defp timestamp(datetime),
    do: datetime |> DateTime.shift_zone!(Brando.timezone()) |> Calendar.strftime("%d.%m.%Y %H:%M")

  defp author(%{author: %{name: name}}) when is_binary(name), do: name
  defp author(_), do: gettext("Unknown user")

  defp excerpt(""), do: gettext("Cleared")

  defp excerpt(text) do
    # All lines, so versions that share an opening line still tell apart.
    line = text |> String.split("\n", trim: true) |> Enum.join(" · ")
    if String.length(line) > 160, do: String.slice(line, 0, 160) <> "…", else: line
  end
end
