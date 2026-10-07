defmodule BrandoAdmin.Components.Form.NotesDrawer do
  @moduledoc """
  The entry's notes, docked beside the editor: the threads in Open and
  Resolved tabs, a composer for a new thread and a reply box on each one.
  See `Brando.Notes`.

  The notes load once per entry, here, never per block. What the editor
  shows for them — a count on each block, highlighted text, the field
  marks — is drawn on the client from one `"b:notes"` event
  (`assets/src/Notes`), on sticky attributes, so no block form is re-rendered
  when a note changes.

  The panel opens and closes on the client. A block's note button, a field
  label's note button and "Add note" in the rich text editor push `compose`
  here with the anchor. Changes made elsewhere arrive as `event: :refresh`
  from `BrandoAdmin.LiveView.Form.Hooks`.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Notes
  alias Brando.Notes.Note
  alias BrandoAdmin.Components.Activity

  def mount(socket) do
    {:ok,
     socket
     |> assign(:loaded?, false)
     |> assign(:threads, [])
     |> assign(:names, %{})
     |> assign(:tab, :open)
     |> assign(:query, "")
     |> assign(:composer, nil)
     |> assign(:expanded, MapSet.new())
     |> assign(:nonce, 0)
     |> assign(:open_count, nil)
     |> assign(:error, nil)}
  end

  def update(%{event: :refresh} = msg, socket) do
    own_change? = msg[:origin] == self() and msg[:note_event] != :anchors
    {:ok, if(own_change?, do: socket, else: load(socket))}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(socket.assigns.loaded?, do: socket, else: load(socket))}
  end

  defp load(socket) do
    %{schema: schema, entry_id: entry_id} = socket.assigns

    {threads, names} =
      try do
        threads = Notes.list_threads(schema, entry_id)
        {threads, Notes.mention_names(Enum.flat_map(threads, &[&1 | &1.replies]))}
      rescue
        error ->
          require Logger
          Logger.warning("[Notes] Could not load notes: " <> Exception.message(error))
          {[], %{}}
      end

    socket
    |> assign(:threads, threads)
    |> assign(:names, names)
    |> assign_access()
    |> assign(:loaded?, true)
    |> report_count()
    |> push_decorations()
  end

  # Who may write, and whom they can mention, is read once per entry.
  defp assign_access(%{assigns: %{loaded?: true}} = socket), do: socket

  defp assign_access(%{assigns: %{schema: schema, entry_id: entry_id, current_user: user}} = socket) do
    {can_write?, users} =
      case Brando.Repo.get(schema, entry_id) do
        nil -> {false, []}
        entry -> {Notes.can_write?(user, entry), Enum.map(Notes.mentionable_users(entry), &%{id: &1.id, name: &1.name})}
      end

    assign(socket, can_write?: can_write?, users: users)
  rescue
    _ -> assign(socket, can_write?: false, users: [])
  end

  # The toolbar's count lives in the form; tell it only when it changes.
  defp report_count(socket) do
    count = Enum.count(socket.assigns.threads, &(!Note.resolved?(&1)))

    if count != socket.assigns.open_count do
      send_update(BrandoAdmin.Components.Form, id: socket.assigns.form_id, action: :notes_count, count: count)
    end

    assign(socket, :open_count, count)
  end

  defp push_decorations(socket) do
    open = Enum.reject(socket.assigns.threads, &Note.resolved?/1)

    blocks =
      open
      |> Enum.filter(&(&1.block_uid && is_nil(&1.detached_at)))
      |> Enum.frequencies_by(& &1.block_uid)
      |> Map.new(fn {uid, count} -> {uid, %{count: count, label: open_label(count)}} end)

    fields =
      open
      |> Enum.filter(&(is_nil(&1.block_uid) && &1.field_path))
      |> Enum.frequencies_by(& &1.field_path)
      |> Map.new(fn {path, count} -> {path, %{count: count, label: open_label(count)}} end)

    marks =
      for note <- open,
          note.range,
          note.block_uid,
          is_nil(note.text_removed_at),
          is_nil(note.detached_at),
          do: %{uid: note.block_uid, id: note.id}

    push_event(socket, "b:notes", %{
      panel: socket.assigns.id,
      enabled: socket.assigns.can_write?,
      blocks: blocks,
      fields: fields,
      marks: marks,
      labels: %{add: gettext("Add note"), notes: gettext("Notes")}
    })
  end

  defp open_label(count), do: ngettext("%{count} open", "%{count} open", count)

  ## Events

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["open", "resolved"] do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
  end

  def handle_event("search", %{"q" => query}, socket), do: {:noreply, assign(socket, :query, String.trim(query))}

  def handle_event("toggle_thread", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded = socket.assigns.expanded

    expanded = if MapSet.member?(expanded, id), do: MapSet.delete(expanded, id), else: MapSet.put(expanded, id)
    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("new_note", _, socket), do: {:noreply, compose(socket, %{})}

  def handle_event("compose", params, socket) do
    anchor =
      params
      |> Map.take(["block_uid", "field_path", "anchor_label", "quote", "tiptap_id", "token"])
      |> Map.reject(fn {_, value} -> value in [nil, ""] end)

    {:noreply, compose(socket, anchor)}
  end

  def handle_event("cancel_compose", _, socket), do: {:noreply, cancel_compose(socket)}

  def handle_event("create", %{"note" => params}, socket) do
    %{composer: composer, schema: schema, entry_id: entry_id, current_user: user} = socket.assigns

    attrs =
      %{
        "body" => params["body"],
        "mentions" => mention_ids(params),
        "block_uid" => composer["block_uid"],
        "field_path" => composer["field_path"],
        "anchor_label" => composer["anchor_label"],
        "range" => composer["quote"] && %{"quote" => composer["quote"]}
      }
      |> Map.reject(fn {_, value} -> is_nil(value) end)

    case Notes.create_thread(schema, entry_id, user, attrs) do
      {:ok, note, mentioned} ->
        notify_mentioned(socket, mentioned)

        socket =
          if composer["tiptap_id"] do
            push_event(socket, "b:tiptap:note:#{composer["tiptap_id"]}", %{token: composer["token"], note_id: note.id})
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:composer, nil)
         |> assign(:tab, :open)
         |> assign(:error, nil)
         |> load()
         |> push_event("b:notes:created", %{id: note.id})}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event("reply", %{"thread" => thread_id, "reply" => params}, socket) do
    with %Note{} = thread <- fetch_thread(socket, thread_id),
         {:ok, _reply, mentioned} <-
           Notes.reply(thread, socket.assigns.current_user, %{"body" => params["body"], "mentions" => mention_ids(params)}) do
      notify_mentioned(socket, mentioned)
      {:noreply, socket |> assign(:error, nil) |> update(:nonce, &(&1 + 1)) |> load()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
      _ -> {:noreply, load(socket)}
    end
  end

  def handle_event("resolve", %{"id" => id}, socket), do: resolution(socket, id, &Notes.resolve/2)
  def handle_event("reopen", %{"id" => id}, socket), do: resolution(socket, id, &Notes.reopen/2)

  defp resolution(socket, id, fun) do
    with %Note{} = thread <- fetch_thread(socket, id),
         {:ok, _} <- fun.(thread, socket.assigns.current_user) do
      {:noreply, socket |> assign(:error, nil) |> load()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
      _ -> {:noreply, load(socket)}
    end
  end

  defp compose(socket, anchor) do
    socket
    |> cancel_pending_mark()
    |> assign(:composer, anchor)
    |> assign(:tab, :open)
    |> assign(:error, nil)
    |> update(:nonce, &(&1 + 1))
  end

  defp cancel_compose(socket) do
    socket
    |> cancel_pending_mark()
    |> assign(:composer, nil)
    |> assign(:error, nil)
  end

  # A text note that is not written after all leaves the text unmarked.
  defp cancel_pending_mark(%{assigns: %{composer: %{"tiptap_id" => tiptap_id, "token" => token}}} = socket),
    do: push_event(socket, "b:tiptap:note:#{tiptap_id}", %{token: token, note_id: nil})

  defp cancel_pending_mark(socket), do: socket

  defp fetch_thread(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    case Notes.get_note(id) do
      %Note{parent_id: nil, entry_id: entry_id} = note ->
        # The form's entry id comes from the URL, as a string.
        if to_string(entry_id) == to_string(socket.assigns.entry_id) and
             note.entry_type == Notes.entry_type(socket.assigns.schema),
           do: note

      _ ->
        nil
    end
  end

  defp mention_ids(params) do
    (params["mentions"] || "")
    |> to_string()
    |> String.split(",", trim: true)
  end

  # Mentioned users who are online see a toast, in their own language.
  defp notify_mentioned(socket, mentioned) do
    author = socket.assigns.current_user.name
    title = socket.assigns.entry_title

    for user <- mentioned, user.id != socket.assigns.current_user.id do
      language = to_string(user.language || Brando.config(:default_admin_language) || "en")

      message =
        Gettext.with_locale(Brando.Gettext, language, fn ->
          gettext("%{name} mentioned you in a note on %{title}", name: author, title: title)
        end)

      BrandoAdmin.Toast.send_to(user, message)
    end
  end

  defp error_message(:forbidden), do: gettext("You can't add notes to this entry.")
  defp error_message(:not_found), do: gettext("This entry no longer exists.")

  defp error_message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :body),
      do: gettext("Write something first."),
      else: gettext("The note could not be saved.")
  end

  defp error_message(_), do: gettext("The note could not be saved.")

  ## Rendering

  def render(assigns) do
    {open, resolved} = Enum.split_with(assigns.threads, &(!Note.resolved?(&1)))

    visible =
      case assigns.tab do
        :open -> open
        :resolved -> resolved |> Enum.reverse() |> filter_threads(assigns.query, assigns.names)
      end

    assigns =
      assign(assigns,
        open: open,
        resolved: resolved,
        visible: visible,
        users_json: Jason.encode!(assigns.users)
      )

    ~H"""
    <aside
      id={@id}
      class="notes-panel"
      aria-label={gettext("Notes")}
      data-notes-panel
      data-mention-users={@users_json}
      data-mention-empty={gettext("No one by that name")}
    >
      <div class="notes-panel-inner">
        <header class="notes-header">
          <h2 id={"#{@id}-title"}>{gettext("Notes")}</h2>
          <nav class="pill-tabs pill-tabs--small notes-tabs" aria-label={gettext("Notes")}>
            <button
              type="button"
              aria-pressed={to_string(@tab == :open)}
              phx-click="tab"
              phx-value-tab="open"
              phx-target={@myself}
            >
              {gettext("Open")} <span class="pill-tabs-count">{length(@open)}</span>
            </button>
            <button
              type="button"
              aria-pressed={to_string(@tab == :resolved)}
              phx-click="tab"
              phx-value-tab="resolved"
              phx-target={@myself}
            >
              {gettext("Resolved")} <span class="pill-tabs-count">{length(@resolved)}</span>
            </button>
          </nav>
          <button
            type="button"
            class="notes-close"
            phx-click={JS.dispatch("brando:notes:close")}
            aria-label={gettext("Close notes")}
          >
            <.icon name="x" />
          </button>
        </header>

        <div class="notes-body">
          <p :if={@error} class="notes-error" role="alert">{@error}</p>

          <.composer
            :if={@composer}
            id={"#{@id}-composer-#{@nonce}"}
            composer={@composer}
            myself={@myself}
          />

          <div :if={@tab == :open && !@composer && @can_write?} class="notes-actions">
            <button type="button" class="notes-new" phx-click="new_note" phx-target={@myself}>
              <.icon name="message-square-plus" />
              {gettext("Note on the entry")}
            </button>
          </div>

          <form
            :if={@tab == :resolved && @resolved != []}
            id={"#{@id}-search"}
            class="notes-search"
            phx-change="search"
            phx-submit="search"
            phx-target={@myself}
          >
            <label class="visually-hidden" for={"#{@id}-q"}>{gettext("Search resolved notes")}</label>
            <input
              id={"#{@id}-q"}
              type="search"
              name="q"
              value={@query}
              placeholder={gettext("Search resolved notes")}
              phx-debounce="200"
              autocomplete="off"
            />
          </form>

          <p :if={@visible == [] && !@composer} class="notes-empty">
            <%= cond do %>
              <% @tab == :open && @can_write? -> %>
                {gettext("No open notes. Add one from a block, a field label or selected text, or on the entry as a whole.")}
              <% @tab == :open -> %>
                {gettext("No open notes.")}
              <% @query != "" -> %>
                {gettext("No resolved notes match.")}
              <% true -> %>
                {gettext("No resolved notes.")}
            <% end %>
          </p>

          <.thread
            :for={thread <- @visible}
            thread={thread}
            names={@names}
            id={"#{@id}-thread-#{thread.id}"}
            collapsed={Note.resolved?(thread) && !MapSet.member?(@expanded, thread.id)}
            can_write?={@can_write?}
            nonce={@nonce}
            myself={@myself}
          />
        </div>

        <footer class="notes-footer">
          <p><.icon name="bell" />{gettext("People you mention get a toast if they are online, and an email.")}</p>
          <p>
            <.icon name="clock" />{gettext(
              "Notes are kept when a revision is restored. A note on a deleted block is kept as detached."
            )}
          </p>
        </footer>
      </div>
    </aside>
    """
  end

  defp filter_threads(threads, "", _names), do: threads

  defp filter_threads(threads, query, names) do
    query = String.downcase(query)

    Enum.filter(threads, fn thread ->
      [
        thread.anchor_label,
        thread.range && thread.range["quote"] | Enum.map([thread | thread.replies], &message_text(&1, names))
      ]
      |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), query)))
    end)
  end

  defp message_text(note, names) do
    Notes.plain_text(note.body, names) <> " " <> ((note.author && note.author.name) || "")
  end

  attr :id, :string, required: true
  attr :composer, :map, required: true
  attr :myself, :any, required: true

  defp composer(assigns) do
    ~H"""
    <form
      id={@id}
      class="note-composer"
      phx-submit="create"
      phx-target={@myself}
      aria-label={gettext("New note")}
    >
      <.anchor_line anchor={anchor_from(@composer)} />
      <div class="note-input">
        <textarea
          id={"#{@id}-body"}
          phx-update="ignore"
          name="note[body]"
          rows="3"
          placeholder={gettext("Write a note. Type @ to mention someone.")}
          aria-label={gettext("Note")}
          phx-hook="Brando.NoteComposer"
          data-submit-on-enter
          phx-mounted={JS.focus()}
        ></textarea>
        <input id={"#{@id}-mentions"} type="hidden" name="note[mentions]" value="" data-mentions phx-update="ignore" />
        <div id={"#{@id}-picker"} class="note-mention-picker" phx-update="ignore" hidden></div>
      </div>
      <p :if={@composer["quote"]} class="note-composer-hint">
        {gettext("The text is marked when you save the entry.")}
      </p>
      <div class="note-composer-actions">
        <button type="button" class="note-button" phx-click="cancel_compose" phx-target={@myself}>
          {gettext("Cancel")}
        </button>
        <button type="submit" class="note-button is-primary">{gettext("Add note")}</button>
      </div>
    </form>
    """
  end

  defp anchor_from(composer) do
    %{
      block_uid: composer["block_uid"],
      field_path: composer["field_path"],
      anchor_label: composer["anchor_label"],
      range: composer["quote"] && %{"quote" => composer["quote"]},
      detached_at: nil,
      text_removed_at: nil
    }
  end

  attr :id, :string, required: true
  attr :thread, :any, required: true
  attr :names, :map, required: true
  attr :collapsed, :boolean, required: true
  attr :can_write?, :boolean, required: true
  attr :nonce, :integer, required: true
  attr :myself, :any, required: true

  defp thread(assigns) do
    assigns =
      assign(assigns,
        messages: [assigns.thread | assigns.thread.replies],
        resolved?: Note.resolved?(assigns.thread)
      )

    ~H"""
    <article
      id={@id}
      class={["note-thread", @resolved? && "is-resolved", @collapsed && "is-collapsed"]}
      data-note-id={@thread.id}
      data-note-block={@thread.block_uid}
    >
      <.anchor_line anchor={@thread} locate={!@thread.detached_at && (@thread.block_uid || @thread.field_path)} />

      <ol class="note-messages">
        <li :for={{message, index} <- Enum.with_index(@messages)} :if={!@collapsed || index == 0} class="note-message">
          <Activity.avatar user={message.author} />
          <div class="note-message-copy">
            <p class="note-message-meta">
              <strong>{(message.author && message.author.name) || gettext("Deleted user")}</strong>
              <time datetime={DateTime.to_iso8601(message.inserted_at)} title={BrandoAdmin.Dates.full(message.inserted_at)}>
                {when_label(message.inserted_at)}
              </time>
            </p>
            <p class="note-body" phx-no-format><.body body={message.body} names={@names} /></p>
          </div>
        </li>
      </ol>

      <p :if={@resolved?} class="note-resolution">
        <.icon name="circle-check" />
        <span :if={@thread.resolved_by}>
          {gettext("Resolved by %{name}", name: @thread.resolved_by.name)} · {when_label(@thread.resolved_at)}
        </span>
        <span :if={!@thread.resolved_by}>{gettext("Resolved")} · {when_label(@thread.resolved_at)}</span>
        <button
          :if={length(@messages) > 1}
          type="button"
          class="note-toggle"
          phx-click="toggle_thread"
          phx-value-id={@thread.id}
          phx-target={@myself}
          aria-expanded={to_string(!@collapsed)}
        >
          {if @collapsed,
            do: ngettext("Show thread (%{count} message)", "Show thread (%{count} messages)", length(@messages)),
            else: gettext("Collapse")}
        </button>
        <button
          :if={@can_write?}
          type="button"
          class="note-reopen"
          phx-click="reopen"
          phx-value-id={@thread.id}
          phx-target={@myself}
        >
          <.icon name="rotate-ccw" />{gettext("Reopen")}
        </button>
      </p>

      <form
        :if={!@resolved? && @can_write?}
        id={"#{@id}-reply-#{@nonce}"}
        class="note-reply"
        phx-submit="reply"
        phx-target={@myself}
      >
        <input type="hidden" name="thread" value={@thread.id} />
        <div class="note-input">
          <textarea
            id={"#{@id}-reply-#{@nonce}-body"}
            phx-update="ignore"
            name="reply[body]"
            rows="1"
            placeholder={gettext("Reply…")}
            aria-label={gettext("Reply")}
            phx-hook="Brando.NoteComposer"
            data-submit-on-enter
          ></textarea>
          <input
            id={"#{@id}-reply-#{@nonce}-mentions"}
            type="hidden"
            name="reply[mentions]"
            value=""
            data-mentions
            phx-update="ignore"
          />
          <div id={"#{@id}-reply-#{@nonce}-picker"} class="note-mention-picker" phx-update="ignore" hidden></div>
          <button type="submit" class="note-reply-send" aria-label={gettext("Send reply")}>
            <.icon name="corner-down-left" />
          </button>
          <button type="button" class="note-resolve" phx-click="resolve" phx-value-id={@thread.id} phx-target={@myself}>
            <.icon name="circle-check" />{gettext("Resolve")}
          </button>
        </div>
      </form>
    </article>
    """
  end

  attr :anchor, :any, required: true
  attr :locate, :any, default: false

  defp anchor_line(assigns) do
    assigns = assign(assigns, kind: anchor_kind(assigns.anchor))

    ~H"""
    <div class={["note-anchor", "is-#{@kind}"]}>
      <button
        :if={@locate}
        type="button"
        class="note-anchor-link"
        phx-click={JS.dispatch("brando:notes:locate")}
        data-block-uid={@anchor.block_uid}
        data-field-path={@anchor.field_path}
        data-note-id={Map.get(@anchor, :id)}
        title={gettext("Show in the editor")}
      >
        <.anchor_content anchor={@anchor} kind={@kind} />
      </button>
      <span :if={!@locate} class="note-anchor-link">
        <.anchor_content anchor={@anchor} kind={@kind} />
      </span>
      <span :if={@anchor.detached_at} class="note-state is-detached">
        <.icon name="unlink" />{gettext("Detached")}
      </span>
      <span :if={@anchor.text_removed_at && !@anchor.detached_at} class="note-state">
        {gettext("Text removed")}
      </span>
    </div>
    """
  end

  attr :anchor, :any, required: true
  attr :kind, :atom, required: true

  defp anchor_content(assigns) do
    ~H"""
    <.icon name={anchor_icon(@kind)} />
    <span class="note-anchor-label">{anchor_label(@anchor, @kind)}</span>
    <span :if={@kind == :text} class="note-quote">“{quote_excerpt(@anchor.range["quote"])}”</span>
    """
  end

  defp anchor_kind(%{block_uid: nil, field_path: nil}), do: :entry
  defp anchor_kind(%{block_uid: nil}), do: :field
  defp anchor_kind(%{range: %{"quote" => _}, text_removed_at: nil}), do: :text
  defp anchor_kind(%{field_path: nil}), do: :block
  defp anchor_kind(%{range: %{"quote" => _}}), do: :block
  defp anchor_kind(_), do: :field

  defp anchor_icon(:entry), do: "file-text"
  defp anchor_icon(:block), do: "square-dashed"
  defp anchor_icon(:text), do: "text-align-start"
  defp anchor_icon(:field), do: "text-cursor-input"

  defp anchor_label(_anchor, :entry), do: gettext("Whole entry")

  defp anchor_label(%{anchor_label: label, field_path: nil}, :block) when label not in [nil, ""],
    do: label <> " · " <> gettext("whole block")

  defp anchor_label(%{anchor_label: label}, _kind) when label not in [nil, ""], do: label
  defp anchor_label(_anchor, :block), do: gettext("Block")
  defp anchor_label(_anchor, :text), do: gettext("Text")
  defp anchor_label(_anchor, _kind), do: gettext("Field")

  defp quote_excerpt(text) when is_binary(text) do
    if String.length(text) > 40, do: String.slice(text, 0, 38) <> "…", else: text
  end

  defp quote_excerpt(_), do: ""

  attr :body, :string, required: true
  attr :names, :map, required: true

  # On one line: the body keeps its own line breaks (`white-space: pre-wrap`),
  # so the template must not add any.
  defp body(assigns) do
    assigns = assign(assigns, :segments, Notes.segments(assigns.body))

    ~H"""
    <span :for={segment <- @segments} class={segment_class(segment)} phx-no-format>{segment_text(segment, @names)}</span>
    """
  end

  defp segment_class({:mention, _}), do: "note-mention"
  defp segment_class(_), do: nil

  defp segment_text({:mention, id}, names), do: "@" <> Map.get(names, id, gettext("unknown"))
  defp segment_text({:text, text}, _names), do: text

  defp when_label(datetime) do
    date = datetime |> DateTime.shift_zone!(Brando.timezone()) |> DateTime.to_date()
    today = DateTime.utc_now() |> DateTime.shift_zone!(Brando.timezone()) |> DateTime.to_date()

    case Date.diff(today, date) do
      0 -> Activity.time(datetime)
      1 -> gettext("Yesterday")
      _ -> Activity.short_date(date)
    end
  end
end
