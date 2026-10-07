defmodule Brando.Notes do
  @moduledoc """
  Notes editors leave each other on an entry, in threads with replies.

  A note belongs to the entry, not to a revision: restoring a revision keeps
  every note. A thread can anchor to

    * the entry as a whole,
    * a block (`block_uid`),
    * a field (`field_path`): an entry field such as `meta_description`, or,
      with a block, a field inside it (`ref:<uid>` for a ref, `var:<id>` for
      a variable),
    * a text range in a block's rich text (`range`, with the quoted text).
      The text carries a mark, `<span data-brando-note="<id>">`, that the
      admin's editor highlights and that `strip_marks/1` removes from every
      render, so it never reaches the site or the live preview.

  When the entry is saved (`entry_saved/2`), the anchors are checked against
  the saved blocks: a thread whose block is gone is shown as detached rather
  than deleted, and one whose marked text is gone becomes a note on its block,
  marked "text removed". Both clear again if a revision brings them back.

  Anyone who may update the entry may add, reply to, resolve and reopen
  notes (`can_write?/2`). A note's body is plain text; `<@12>` mentions user
  12. Mentioned users get one email at most every ten minutes, collecting
  what they were mentioned in meanwhile (`Brando.Worker.NoteMentions`).

  Notes live in the site's own schema, like revisions. Deleting an entry
  soft-deletes its notes, restoring it from the trash restores them, and
  purging it removes them. Adding, resolving and reopening a thread is
  recorded in the entry's activity (`Brando.Activity`).

  Changes are broadcast on the entry's `"notes"` topic
  (`Brando.Tenant.Topic.entry/3`) as `{:notes_changed, %{...}}`.
  """

  import Ecto.Query

  alias Brando.Notes.Mention
  alias Brando.Notes.Note
  alias Brando.Repo
  alias Brando.Tenant.Topic
  alias Brando.Users.User

  require Logger

  @mark_attribute "data-brando-note"
  @mention_token ~r/<@(\d+)>/
  @email_interval 600

  ## Reading

  @doc "Notes name their entry's schema as a string, as revisions and activity events do."
  def entry_type(schema) when is_atom(schema), do: to_string(schema)

  @doc """
  An entry's threads, oldest first, each with its replies, authors and the
  user who resolved it.
  """
  def list_threads(schema, entry_id) do
    replies = from(r in Note, where: is_nil(r.deleted_at), order_by: [asc: r.inserted_at, asc: r.id])

    schema
    |> entry_query(entry_id)
    |> where([n], is_nil(n.parent_id))
    |> order_by([n], asc: n.inserted_at, asc: n.id)
    |> preload(author: :avatar, resolved_by: [], replies: ^{replies, author: :avatar})
    |> Repo.all()
  end

  @doc "How many of an entry's threads are open."
  def count_open(schema, entry_id) do
    schema
    |> entry_query(entry_id)
    |> where([n], is_nil(n.parent_id) and is_nil(n.resolved_at))
    |> Repo.aggregate(:count)
  end

  @doc "A thread or reply by id, unless deleted."
  def get_note(id) do
    Repo.one(from(n in Note, where: n.id == ^id and is_nil(n.deleted_at)))
  end

  @doc """
  The notes `user_id` is mentioned in, newest first, with each note's author:
  `[%Mention{note: %Note{}}]`. Options: `:limit` (default 50), `:unsent`
  (only those not yet emailed).
  """
  def mentions_for(user_id, opts \\ []) do
    query =
      from(m in Mention,
        join: n in assoc(m, :note),
        where: m.user_id == ^user_id and is_nil(n.deleted_at),
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^Keyword.get(opts, :limit, 50),
        preload: [note: {n, author: :avatar}]
      )

    query = if Keyword.get(opts, :unsent), do: where(query, [m], is_nil(m.emailed_at)), else: query
    Repo.all(query)
  end

  defp entry_query(schema, entry_id) do
    type = entry_type(schema)
    entry_id = to_integer(entry_id)
    from(n in Note, where: n.entry_type == ^type and n.entry_id == ^entry_id and is_nil(n.deleted_at))
  end

  ## Permissions

  @doc """
  Whether `user` may add, reply to, resolve and reopen notes on `entry`:
  anyone who may update it.
  """
  def can_write?(%User{} = user, entry) do
    not Brando.Authorization.enabled?() or
      Brando.Authorization.can?(Brando.Authorization.Scope.current(user), :update, entry)
  end

  def can_write?(_, _), do: false

  @doc """
  The users who can be mentioned on `entry`: active accounts that may read
  it, by name.
  """
  def mentionable_users(entry) do
    users =
      from(u in User,
        where: u.active == true and is_nil(u.deleted_at),
        order_by: [asc: u.name, asc: u.id],
        preload: [:avatar]
      )
      |> Repo.all()

    if Brando.Authorization.enabled?(),
      do: Enum.filter(users, &Brando.Authorization.can?(Brando.Authorization.Scope.current(&1), :read, entry)),
      else: users
  end

  ## Writing

  @doc """
  Starts a thread on `entry` (`schema` and `entry_id`) as `user`. `attrs`:
  `body`, and optionally the anchor (`block_uid`, `field_path`, `range`,
  `anchor_label`) and `mentions`, the ids of users named in the body as
  `@Name` (see `encode_mentions/2`).

  Returns `{:ok, note, mentioned_users}`.
  """
  def create_thread(schema, entry_id, %User{} = user, attrs) do
    with {:ok, entry} <- fetch_entry(schema, entry_id),
         :ok <- authorize(user, entry),
         attrs = normalize_attrs(attrs),
         {body, mentioned} = encode_mentions(attrs["body"] || "", mention_candidates(entry, attrs)),
         fields = %{"body" => body, "author_id" => user.id, "entry_type" => entry_type(schema), "entry_id" => entry.id},
         changeset = Note.thread_changeset(%Note{}, Map.merge(attrs, fields)),
         {:ok, note} <- insert_with_mentions(changeset, mentioned, user) do
      record(:note_added, entry, user, note)
      broadcast(schema, entry.id, :added, note)
      {:ok, note, mentioned}
    end
  end

  @doc """
  Replies to `thread` as `user`. `attrs` as for `create_thread/4`, without
  the anchor. Replying to a resolved thread reopens it. Returns
  `{:ok, reply, mentioned_users}`.
  """
  def reply(%Note{parent_id: nil} = thread, %User{} = user, attrs) do
    schema = schema_of(thread)

    with {:ok, entry} <- fetch_entry(schema, thread.entry_id),
         :ok <- authorize(user, entry),
         attrs = normalize_attrs(attrs),
         {body, mentioned} = encode_mentions(attrs["body"] || "", mention_candidates(entry, attrs)),
         changeset = Note.reply_changeset(%Note{}, thread, %{"body" => body, "author_id" => user.id}),
         {:ok, reply} <- insert_with_mentions(changeset, mentioned, user) do
      if Note.resolved?(thread), do: set_resolved(thread, entry, user, false)
      broadcast(schema, entry.id, :replied, thread)
      {:ok, reply, mentioned}
    end
  end

  def reply(%Note{}, _user, _attrs), do: {:error, :not_a_thread}

  @doc "Resolves `thread` as `user`."
  def resolve(%Note{} = thread, %User{} = user), do: change_resolution(thread, user, true)

  @doc "Reopens a resolved `thread` as `user`."
  def reopen(%Note{} = thread, %User{} = user), do: change_resolution(thread, user, false)

  defp change_resolution(%Note{parent_id: nil} = thread, user, resolve?) do
    schema = schema_of(thread)

    with {:ok, entry} <- fetch_entry(schema, thread.entry_id),
         :ok <- authorize(user, entry) do
      if Note.resolved?(thread) == resolve?,
        do: {:ok, thread},
        else: set_resolved(thread, entry, user, resolve?)
    end
  end

  defp change_resolution(%Note{}, _user, _resolve?), do: {:error, :not_a_thread}

  defp set_resolved(thread, entry, user, resolve?) do
    attrs =
      if resolve?,
        do: %{resolved_at: DateTime.utc_now(), resolved_by_id: user.id},
        else: %{resolved_at: nil, resolved_by_id: nil}

    with {:ok, updated} <- thread |> Ecto.Changeset.change(attrs) |> Repo.update() do
      record(if(resolve?, do: :note_resolved, else: :note_reopened), entry, user, updated)
      broadcast(entry.__struct__, entry.id, if(resolve?, do: :resolved, else: :reopened), updated)
      {:ok, updated}
    end
  end

  # Writing about yourself mentions no one.
  defp insert_with_mentions(changeset, mentioned, author) do
    others = Enum.reject(mentioned, &(&1.id == author.id))

    case Repo.transaction(fn -> insert_note!(changeset, others) end) do
      {:ok, note} ->
        Enum.each(others, &schedule_mention_email(&1.id))
        {:ok, note}

      error ->
        error
    end
  end

  defp insert_note!(changeset, mentioned) do
    case Repo.insert(changeset) do
      {:ok, note} ->
        now = DateTime.utc_now()
        rows = Enum.map(mentioned, &%{note_id: note.id, user_id: &1.id, inserted_at: now})
        if rows != [], do: Repo.insert_all(Mention, rows, on_conflict: :nothing)
        note

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp authorize(user, entry), do: if(can_write?(user, entry), do: :ok, else: {:error, :forbidden})

  defp fetch_entry(schema, entry_id) do
    case Repo.get(schema, to_integer(entry_id)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp normalize_attrs(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    case attrs["range"] do
      %{} = range -> Map.put(attrs, "range", Map.new(range, fn {key, value} -> {to_string(key), value} end))
      _ -> Map.delete(attrs, "range")
    end
  end

  # Only users who may read the entry can be mentioned.
  defp mention_candidates(entry, attrs) do
    ids =
      attrs
      |> Map.get("mentions", [])
      |> List.wrap()
      |> Enum.map(&to_integer/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      []
    else
      allowed = entry |> mentionable_users() |> Map.new(&{&1.id, &1})
      ids |> Enum.map(&allowed[&1]) |> Enum.reject(&is_nil/1)
    end
  end

  defp schema_of(%Note{entry_type: type}), do: String.to_existing_atom(type)

  ## Mentions in the body

  @doc """
  Turns each `@Name` of `users` in `text` into the token `<@id>`, longest
  name first so "@Anna" is not read as "@Ann". Returns `{body, users}` with
  the users that are still named in it.
  """
  def encode_mentions(text, users) do
    users
    |> Enum.sort_by(&(-String.length(&1.name || "")))
    |> Enum.reduce({text, []}, fn user, {body, named} ->
      handle = "@" <> (user.name || "")

      if user.name not in [nil, ""] and String.contains?(body, handle),
        do: {String.replace(body, handle, "<@#{user.id}>"), [user | named]},
        else: {body, named}
    end)
    |> then(fn {body, named} -> {body, Enum.reverse(named)} end)
  end

  @doc "The ids of the users a body mentions."
  def mentioned_ids(body) when is_binary(body) do
    @mention_token |> Regex.scan(body, capture: :all_but_first) |> List.flatten() |> Enum.map(&String.to_integer/1)
  end

  def mentioned_ids(_), do: []

  @doc """
  A body as parts to render: `{:text, text}` and `{:mention, id}`.
  """
  def segments(body) when is_binary(body) do
    @mention_token
    |> Regex.split(body, include_captures: true, trim: true)
    |> Enum.map(fn part ->
      case Regex.run(@mention_token, part, capture: :all_but_first) do
        [id] when byte_size(part) == byte_size(id) + 3 -> {:mention, String.to_integer(id)}
        _ -> {:text, part}
      end
    end)
  end

  def segments(_), do: []

  @doc "A body as plain text, each mention as `@Name` from `names` (`%{id => name}`)."
  def plain_text(body, names) do
    Regex.replace(@mention_token, body || "", fn _, id ->
      "@" <> (Map.get(names, String.to_integer(id)) || "?")
    end)
  end

  @doc "The names of the users a list of notes mentions, `%{id => name}`."
  def mention_names(notes) do
    ids = notes |> Enum.flat_map(&mentioned_ids(&1.body)) |> Enum.uniq()

    if ids == [],
      do: %{},
      else: Map.new(Repo.all(from(u in User, where: u.id in ^ids, select: {u.id, u.name})))
  end

  ## Anchors

  @doc """
  Checks an entry's anchored threads against its saved blocks, after a save
  or a restored revision: sets or clears `detached_at` (the block is gone)
  and `text_removed_at` (the marked text is gone from its block). Broadcasts
  when anything changed. Never fails the save that called it.
  """
  def entry_saved(schema, %{id: id}) when is_integer(id), do: reconcile(schema, id)
  def entry_saved(_schema, _entry), do: :ok

  @doc false
  def reconcile(schema, entry_id) do
    anchored =
      schema
      |> entry_query(entry_id)
      |> where([n], is_nil(n.parent_id) and not is_nil(n.block_uid))
      |> Repo.all(guarded())

    if anchored == [] do
      :ok
    else
      blocks = block_marks(schema, entry_id)
      now = DateTime.utc_now()

      changed =
        Enum.filter(anchored, fn note ->
          changes = anchor_changes(note, blocks, now)
          changes != %{} and match?({:ok, _}, note |> Ecto.Changeset.change(changes) |> Repo.update())
        end)

      if changed != [], do: broadcast(schema, to_integer(entry_id), :anchors, nil)
      :ok
    end
  rescue
    error ->
      Logger.warning("[Brando.Notes] Could not check note anchors: " <> Exception.message(error))
      :ok
  end

  defp anchor_changes(note, blocks, now) do
    case Map.fetch(blocks, note.block_uid) do
      :error ->
        if note.detached_at, do: %{}, else: %{detached_at: now}

      {:ok, marks} ->
        text_removed_at =
          cond do
            is_nil(note.range) -> nil
            MapSet.member?(marks, note.id) -> nil
            true -> note.text_removed_at || now
          end

        %{detached_at: nil, text_removed_at: text_removed_at}
        |> Enum.reject(fn {key, value} -> Map.get(note, key) == value end)
        |> Map.new()
    end
  end

  # `%{block_uid => MapSet of note ids marked in the block's own text}` for
  # every block of the saved entry, children included.
  defp block_marks(schema, entry_id) do
    entry_id = to_integer(entry_id)

    roots =
      if function_exported?(schema, :__blocks_fields__, 0) do
        Enum.flat_map(schema.__blocks_fields__(), fn %{name: name} ->
          entry_block_schema = schema.__schema__(:association, :"entry_#{name}").related
          Repo.all(from(eb in entry_block_schema, where: eb.entry_id == ^entry_id, select: eb.block_id))
        end)
      else
        []
      end

    blocks = collect_blocks(roots, %{})
    ids = Map.keys(blocks)
    marked = marked_texts(ids)

    Map.new(blocks, fn {id, uid} ->
      marks =
        marked
        |> Map.get(id, [])
        |> Enum.flat_map(&mark_ids/1)
        |> MapSet.new()

      {uid, marks}
    end)
  end

  defp collect_blocks([], acc), do: acc

  defp collect_blocks(ids, acc) do
    found =
      Repo.all(from(b in "content_blocks", where: b.id in ^ids, select: {b.id, b.uid}))

    acc = Enum.reduce(found, acc, fn {id, uid}, acc -> Map.put(acc, id, uid) end)

    children =
      from(b in "content_blocks", where: b.parent_id in ^ids, select: b.id)
      |> Repo.all()
      |> Enum.reject(&Map.has_key?(acc, &1))

    collect_blocks(children, acc)
  end

  # The text of refs and variables (table rows' too) that carry a note mark,
  # by block id.
  defp marked_texts([]), do: %{}

  defp marked_texts(block_ids) do
    pattern = "%#{@mark_attribute}%"

    refs =
      from(r in "content_refs",
        where: r.block_id in ^block_ids and like(fragment("?::text", r.data), ^pattern),
        select: {r.block_id, fragment("?::text", r.data)}
      )

    vars =
      from(v in "content_vars",
        where: v.block_id in ^block_ids and like(v.value, ^pattern),
        select: {v.block_id, v.value}
      )

    row_vars =
      from(v in "content_vars",
        join: t in "content_table_rows",
        on: v.table_row_id == t.id,
        where: t.block_id in ^block_ids and like(v.value, ^pattern),
        select: {t.block_id, v.value}
      )

    [refs, vars, row_vars]
    |> Enum.flat_map(&Repo.all/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @mark_id ~r/data-brando-note=\\?"(\d+)\\?"/

  @doc "The note ids marked in a piece of HTML (or JSON holding it)."
  def mark_ids(text) when is_binary(text) do
    @mark_id |> Regex.scan(text, capture: :all_but_first) |> List.flatten() |> Enum.map(&String.to_integer/1)
  end

  def mark_ids(_), do: []

  @doc """
  Removes note marks from rendered HTML, keeping the text they wrap. Cheap
  when there are none: rendered HTML only pays for a substring check.
  """
  def strip_marks(html) when is_binary(html) do
    if String.contains?(html, @mark_attribute), do: do_strip_marks(html), else: html
  end

  def strip_marks(html), do: html

  @span ~r{<span\b[^>]*>|</span\s*>}i

  defp do_strip_marks(html) do
    @span
    |> Regex.split(html, include_captures: true)
    |> Enum.reduce({[], []}, &strip_part/2)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  # The split leaves each `<span …>` and `</span>` as a part of its own. A
  # closing tag drops when it closes a mark; an opening tag is a mark when it
  # carries the note attribute. Everything else passes through.
  defp strip_part(part, {out, stack}) do
    cond do
      Regex.match?(~r{\A</span\s*>\z}i, part) ->
        case stack do
          [:note | rest] -> {out, rest}
          [_ | rest] -> {[part | out], rest}
          [] -> {[part | out], []}
        end

      Regex.match?(~r/\A<span\b[^>]*>\z/i, part) ->
        if String.contains?(part, @mark_attribute),
          do: {out, [:note | stack]},
          else: {[part | out], [:keep | stack]}

      true ->
        {[part | out], stack}
    end
  end

  ## Entry lifecycle

  @doc """
  The entry was moved to the trash (`soft?`) or deleted: its notes are
  soft-deleted with it, at the entry's own `deleted_at`, or removed.
  """
  def entry_deleted(schema, %{id: id} = entry, soft?) do
    if soft? do
      deleted_at = Map.get(entry, :deleted_at) || DateTime.utc_now()

      schema
      |> entry_query(id)
      |> Repo.update_all([set: [deleted_at: to_utc_usec(deleted_at)]], guarded())
    else
      entries_purged(schema, [id])
    end

    :ok
  rescue
    error -> log_lifecycle_error(error)
  end

  @doc "The entry came back from the trash: the notes trashed with it come back too."
  def entry_restored(schema, %{id: id, deleted_at: %{} = deleted_at}) do
    type = entry_type(schema)
    at = to_utc_usec(deleted_at)

    from(n in Note, where: n.entry_type == ^type and n.entry_id == ^id and n.deleted_at == ^at)
    |> Repo.update_all([set: [deleted_at: nil]], guarded())

    :ok
  rescue
    error -> log_lifecycle_error(error)
  end

  def entry_restored(_schema, _entry), do: :ok

  @doc "Removes the notes of entries deleted for good."
  def entries_purged(_schema, []), do: :ok

  def entries_purged(schema, ids) do
    type = entry_type(schema)
    Repo.delete_all(from(n in Note, where: n.entry_type == ^type and n.entry_id in ^ids), guarded())
    :ok
  rescue
    error -> log_lifecycle_error(error)
  end

  # Entries are saved, trashed and purged inside transactions. Before the
  # `brando_203` migration has run there is no notes table, and a failed
  # statement would abort the caller's transaction: run the first statement
  # in a savepoint, as `Brando.Activity` does, so the save carries on.
  defp guarded do
    if Repo.repo().in_transaction?(), do: [mode: :savepoint], else: []
  end

  defp log_lifecycle_error(error) do
    Logger.warning("[Brando.Notes] Could not update notes: " <> Exception.message(error))
    :ok
  end

  defp to_utc_usec(%DateTime{} = datetime), do: datetime |> DateTime.truncate(:microsecond) |> pad_usec()
  defp to_utc_usec(%NaiveDateTime{} = naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> to_utc_usec()

  defp pad_usec(%DateTime{microsecond: {value, _}} = datetime), do: %{datetime | microsecond: {value, 6}}

  ## Mention emails

  @doc """
  Queues the email for `user_id`'s unsent mentions: now, or ten minutes
  after the last one, so a user gets one email at most every ten minutes.
  """
  def schedule_mention_email(user_id) do
    args = Brando.Tenant.Job.attach_current(%{"user_id" => user_id})
    delay = seconds_until_next_email(user_id, DateTime.utc_now())

    args
    |> Brando.Worker.NoteMentions.new(schedule_in: delay)
    |> Oban.insert()
  rescue
    error ->
      Logger.warning("[Brando.Notes] Could not queue a mention email: " <> Exception.message(error))
      {:error, error}
  end

  @doc """
  Emails `user_id` the mentions not sent yet, unless an email went out less
  than ten minutes ago. Returns `:ok` (sent, or nothing to send) or
  `{:snooze, seconds}` until the next email may go.
  """
  def deliver_mentions(user_id, now \\ DateTime.utc_now()) do
    case seconds_until_next_email(user_id, now) do
      0 -> send_pending_mentions(user_id, now)
      seconds -> {:snooze, seconds}
    end
  end

  defp seconds_until_next_email(user_id, now) do
    last =
      Repo.one(from(m in Mention, where: m.user_id == ^user_id and not is_nil(m.emailed_at), select: max(m.emailed_at)))

    case last do
      nil -> 0
      last -> max(0, @email_interval - DateTime.diff(now, last, :second))
    end
  end

  defp send_pending_mentions(user_id, now) do
    user = Repo.get(User, user_id)
    pending = mentions_for(user_id, unsent: true, limit: 100)

    cond do
      pending == [] ->
        :ok

      is_nil(user) or not user.active or not is_nil(user.deleted_at) ->
        mark_emailed(pending, now)

      true ->
        items = pending |> Enum.reverse() |> Enum.flat_map(&email_item/1)

        if items != [] do
          {:ok, _job} = user |> Brando.Notes.MentionEmail.build(items) |> Brando.Mailer.deliver_later()
        end

        mark_emailed(pending, now)
    end
  end

  defp mark_emailed(mentions, now) do
    ids = Enum.map(mentions, & &1.id)
    Repo.update_all(from(m in Mention, where: m.id in ^ids), set: [emailed_at: now])
    :ok
  end

  defp email_item(%Mention{note: note}) do
    schema = schema_of(note)

    case Repo.get(schema, note.entry_id) do
      nil ->
        []

      entry ->
        names = mention_names([note])

        [
          %{
            author: note.author && note.author.name,
            entry_title: entry_title(schema, entry),
            anchor: note.anchor_label,
            text: plain_text(note.body, names),
            url: entry_url(schema, entry, note)
          }
        ]
    end
  rescue
    _ -> []
  end

  @doc "The entry's title as its identifier shows it."
  def entry_title(schema, entry) do
    identifier =
      if function_exported?(schema, :__has_identifier__, 0) and schema.__has_identifier__(),
        do: schema.__identifier__(entry, skip_cover: true)

    case identifier do
      %{title: title} when is_binary(title) and title != "" -> title
      _ -> Map.get(entry, :title) || Map.get(entry, :name) || "##{entry.id}"
    end
  rescue
    _ -> "##{entry.id}"
  end

  defp entry_url(schema, entry, note) do
    path = schema.__admin_route__(:update, [entry.id])
    query = if note.block_uid, do: "?block=" <> URI.encode_www_form(note.block_uid), else: ""
    String.trim_trailing(Brando.endpoint().url(), "/") <> path <> query
  rescue
    _ -> nil
  end

  ## Activity and broadcasts

  defp record(action, entry, user, note) do
    names = mention_names([note])
    excerpt = note.body |> plain_text(names) |> String.slice(0, 140)

    details =
      %{"note" => note.id, "excerpt" => excerpt}
      |> maybe_put("anchor", note.anchor_label)

    Brando.Activity.record(action, entry, user, details: details)
  rescue
    _ -> :ok
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "The topic an entry's note changes are broadcast on."
  def topic(schema, entry_id), do: Topic.entry("notes", schema, entry_id)

  defp broadcast(schema, entry_id, event, note) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      topic(schema, entry_id),
      {:notes_changed, %{schema: schema, entry_id: entry_id, event: event, note_id: note && note.id, origin: self()}}
    )
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_integer(_), do: nil
end
