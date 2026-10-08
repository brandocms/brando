defmodule Brando.Activity do
  @moduledoc """
  The activity log: who created, changed, published, trashed, restored and
  deleted entries, and when.

  Every Blueprint entry that changes through Brando records an event:
  `Brando.Query.Mutations` (create, update, delete, duplicate), status changes
  from a listing, reordering, restoring from the trash, restoring or
  scheduling a revision, content imports and the trash purge. An event keeps
  the entry's title as it was, the names of the fields that changed and the
  revision the change saved. It does not keep values; the revisions hold the
  content, and Configuration → Activity compares them.

  Notes on an entry record `:note_added`, `:note_resolved` and
  `:note_reopened` (`Brando.Notes`), with the note's opening words.

  The person is the user the change was made as. `source` says how it was
  made when that wasn't by hand in the admin: `:scheduler` (scheduled
  publishing; the user is whoever scheduled it), `:assistant` (an applied
  proposal; the user approved it), `:mcp` (an applied proposal that a tool
  connected over MCP prepared, with the tool's name as `details["client"]`
  when known; the user approved it), `:import` (content transfer) or
  `:system` (no user).

  A change from a content proposal (`Brando.Content.Proposals`, applied or
  undone) also names the proposal (`proposal_id`) and the user who approved
  and applied it (`approver_id`), apart from the agent that prepared it
  (`with_proposal/5`). By kind (`actor_kind/1`), an event is a person's, the
  Assistant's, a connected tool's over MCP, or an automatic job's
  (scheduled publishing and the system).

  Recording never fails a save. An event that can't be written (for example
  before the `brando_193` migration has run) is logged and dropped, inside a
  savepoint so a surrounding transaction carries on.

  ## Configuration

      config :brando, Brando.Activity,
        retention_days: 365,
        ignore: [MyApp.Things.Counter]

  Events older than `retention_days` (default 365) are removed nightly.
  Schemas in `ignore` are not logged. Media (images, files, videos,
  galleries) and Brando's internal records (blocks, variables, revisions,
  identifiers, previews) never are.
  """

  import Ecto.Query

  alias Brando.Activity.Event
  alias Brando.Authorization.Scope
  alias Brando.Repo

  require Logger

  @source_key :brando_activity_source
  @source_details_key :brando_activity_source_details
  @batch_key :brando_activity_batch
  @proposal_key :brando_activity_proposal

  @actor_kinds [:person, :assistant, :mcp, :task]

  @internal [
    Brando.Revisions.Revision,
    Brando.Content.Block,
    Brando.Content.Var,
    Brando.Content.Var.Option,
    Brando.Content.Ref,
    Brando.Content.Identifier,
    Brando.Sites.Preview,
    Brando.Images.Image,
    Brando.Files.File,
    Brando.Videos.Video,
    Brando.Galleries.Gallery,
    Brando.Galleries.GalleryObject,
    Brando.Users.UserConfig
  ]

  # Bookkeeping that every save touches; a change to these alone is not an edit.
  @ignored_fields ~w(id inserted_at updated_at updated_by_id edited_at content_modified_at creator_id sequence deleted_at
                     last_login last_seen config)

  @default_retention_days 365

  ## Context

  @doc """
  Run `fun` with every event it records attributed to `source` (`:scheduler`,
  `:assistant`, `:mcp`, `:import` or `:system`) rather than to the admin.
  `details` are added to each event's details, such as the name of the tool
  behind an `:mcp` change: `%{"client" => "Claude Code"}`.
  """
  def with_source(source, details \\ %{}, fun)
      when source in [:admin, :scheduler, :assistant, :mcp, :import, :system] and is_map(details) do
    previous = Process.put(@source_key, source)
    previous_details = Process.put(@source_details_key, details)

    try do
      fun.()
    after
      if previous, do: Process.put(@source_key, previous), else: Process.delete(@source_key)

      if previous_details,
        do: Process.put(@source_details_key, previous_details),
        else: Process.delete(@source_details_key)
    end
  end

  @doc """
  Run `fun` with every event it records attributed to a content proposal:
  prepared by `source` (`:assistant`, or `:mcp` with the tool's name in
  `details`), from proposal `proposal_id`, and approved and applied by
  `approver` (a user or an authorization scope), as `with_source/3`.
  """
  def with_proposal(source, details, proposal_id, approver, fun) when source in [:assistant, :mcp] do
    previous = Process.put(@proposal_key, %{proposal_id: proposal_id, approver_id: user_id(approver)})

    try do
      with_source(source, details, fun)
    after
      if previous, do: Process.put(@proposal_key, previous), else: Process.delete(@proposal_key)
    end
  end

  @doc """
  Who made a change, by kind: `:person` (by hand in the admin, or a content
  transfer someone ran), `:assistant`, `:mcp` (a tool connected over MCP) or
  `:task` (scheduled publishing and the system's own jobs).
  """
  def actor_kind(%{source: source}) when source in [:assistant, :mcp], do: source
  def actor_kind(%{source: source}) when source in [:scheduler, :system], do: :task
  def actor_kind(_event), do: :person

  @doc "The kinds `actor_kind/1` returns."
  def actor_kinds, do: @actor_kinds

  defp kind_sources(:person), do: [:admin, :import]
  defp kind_sources(:task), do: [:scheduler, :system]
  defp kind_sources(kind), do: [kind]

  @doc "Run `fun` with every event it records sharing one `batch_id`, so the log shows them as one operation."
  def with_batch(batch_id, fun) do
    previous = Process.put(@batch_key, batch_id)

    try do
      fun.()
    after
      if previous, do: Process.put(@batch_key, previous), else: Process.delete(@batch_key)
    end
  end

  @doc "Whether changes to `schema` are logged."
  def logged?(schema) when is_atom(schema) do
    schema not in @internal and schema not in ignored() and function_exported?(schema, :__naming__, 0)
  end

  def logged?(_), do: false

  defp ignored, do: Keyword.get(config(), :ignore, [])

  defp config, do: Brando.config(__MODULE__) || []

  @doc "How many days events are kept."
  def retention_days, do: Keyword.get(config(), :retention_days, @default_retention_days)

  ## Recording

  @doc """
  Record a saved changeset: `:created` for an insert; `:published` or
  `:unpublished` when the status crossed into or out of published; otherwise
  `:updated`. A save that only touched bookkeeping fields records nothing.
  """
  def saved(%Ecto.Changeset{} = changeset, entry, user, revision \\ nil) do
    guard(entry, fn ->
      fields = changed_fields(changeset)
      insert? = changeset.action == :insert or match?(%{__meta__: %{state: :built}}, changeset.data)
      opts = [fields: fields, revision: revision]

      cond do
        insert? -> record(:created, entry, user, [details: status_details(nil, entry)] ++ opts)
        fields == [] -> :ok
        true -> record_update(Map.get(changeset.data, :status), entry, user, opts)
      end
    end)
  end

  defp record_update(status, %{status: status} = entry, user, opts), do: record(:updated, entry, user, opts)

  defp record_update(from, entry, user, opts) do
    action =
      case {from, Map.get(entry, :status)} do
        {_, :published} -> :published
        {:published, _} -> :unpublished
        _ -> :updated
      end

    record(action, entry, user, [details: status_details(from, entry)] ++ opts)
  end

  @doc """
  Record that `entry` was moved to the trash (`soft?` true) or deleted for
  good. `details` add to the event, e.g. `%{"purged" => true}` when the trash
  emptied itself.
  """
  def deleted(entry, user, soft?, details \\ %{}) do
    guard(entry, fn -> record(if(soft?, do: :trashed, else: :deleted), entry, user, details: details) end)
  end

  @doc "Record that `entry` came back from the trash."
  def restored(entry, user), do: guard(entry, fn -> record(:restored, entry, user) end)

  @doc """
  Record that `entry` was set back to `revision`. `replaced` is the revision
  that was active before. A scheduled revision (`publish?: true`) records
  `:published`.
  """
  def revision_restored(entry, user, revision, replaced, opts \\ []) do
    guard(entry, fn ->
      details = if replaced, do: %{"replaced" => replaced}, else: %{}

      if Keyword.get(opts, :publish?, false),
        do: record(:published, entry, user, revision: revision, details: Map.put(details, "scheduled", true)),
        else: record(:revision_restored, entry, user, revision: revision, details: details)
    end)
  end

  @doc "Record that `copy` was made from `original`."
  def duplicated(copy, original, user) do
    guard(copy, fn ->
      record(:duplicated, copy, user,
        details:
          %{"copied_from" => %{"id" => original.id, "title" => title(original)}} |> Map.merge(status_details(nil, copy))
      )
    end)
  end

  @doc "Record that `count` entries of `schema` were put in a new order, `first` now leading."
  def reordered(schema, count, first, user) do
    guard(schema, fn ->
      details = %{"count" => count}
      details = if first, do: Map.put(details, "first", title(first)), else: details

      insert(%{
        action: :reordered,
        schema: to_string(schema),
        user_id: user_id(user),
        source: source(user),
        details: Map.merge(source_details(), details)
      })
    end)
  end

  @doc """
  Record that a content import created (`mode` `:create`) or updated `entry`.
  `label` names where it came from; `fields` are the fields it replaced.
  """
  def imported(entry, user, mode, label, fields \\ []) do
    guard(entry, fn ->
      details = %{"mode" => to_string(mode)}
      details = if label, do: Map.put(details, "from", label), else: details
      record(:imported, entry, user, details: details, fields: fields)
    end)
  end

  @doc """
  Record that undoing a content import set `entry` back (`:update`) or
  removed the entry the import had created (`:delete`).
  """
  def import_undone(entry, user, :update),
    do: guard(entry, fn -> record(:updated, entry, user, details: %{"undo_import" => true}) end)

  def import_undone(entry, user, :delete),
    do: guard(entry, fn -> record(:deleted, entry, user, details: %{"undo_import" => true}) end)

  @doc """
  Record `action` on `entry`. Options: `:fields`, `:revision`, `:details`.

  The change is also announced to `Brando.ContentEvents`, which turns it
  into a content event (`entry.updated` and so on) for webhooks and other
  subscribers.
  """
  def record(action, entry, user, opts \\ []) do
    source = source(user)
    result = record_event(action, entry, user, source, opts)
    Brando.ContentEvents.activity_recorded(action, entry, source, opts)
    result
  end

  defp record_event(action, entry, user, source, opts) do
    insert(%{
      action: action,
      source: source,
      user_id: user_id(user),
      schema: to_string(entry.__struct__),
      entry_id: entry.id,
      title: title(entry),
      language: language(entry),
      fields: Keyword.get(opts, :fields, []),
      revision: Keyword.get(opts, :revision),
      details: Map.merge(source_details(), Keyword.get(opts, :details, %{})),
      batch_id: Process.get(@batch_key)
    })
  end

  @doc """
  Record `action` (`:created`, `:updated` or `:deleted`) on a setting that is
  not a Blueprint entry, such as a webhook. `title` names it in the log;
  `details` say what changed, never secrets. Sends no content event.
  """
  def setting_changed(action, %{__struct__: schema, id: id}, title, user, opts \\ [])
      when action in [:created, :updated, :deleted] do
    insert(%{
      action: action,
      source: source(user),
      user_id: user_id(user),
      schema: to_string(schema),
      entry_id: id,
      title: title,
      fields: Keyword.get(opts, :fields, []),
      details: Map.merge(source_details(), Keyword.get(opts, :details, %{})),
      batch_id: Process.get(@batch_key)
    })
  end

  @doc """
  Record that the client of the MCP connection `grant` called tool `name`
  as `user` (`Brando.MCP.Tools`). Options: `:ok` (whether it succeeded),
  `:token_id` (the access token's row id, never the token) and
  `:duration_ms`. The arguments are not kept; a proposal the call prepared
  is in the Assistant. Sends no content event.
  """
  def tool_called(%{__struct__: schema, id: id, client_name: client}, user, name, opts \\ []) do
    insert(%{
      action: :tool_called,
      source: :mcp,
      user_id: user_id(user),
      schema: to_string(schema),
      entry_id: id,
      title: client,
      details: %{
        "client" => client,
        "tool" => name,
        "ok" => Keyword.get(opts, :ok, true),
        "token" => Keyword.get(opts, :token_id),
        "duration_ms" => Keyword.get(opts, :duration_ms)
      }
    })
  end

  defp guard(%{__struct__: schema} = _entry, fun), do: guard(schema, fun)

  defp guard(schema, fun) when is_atom(schema) do
    if logged?(schema), do: fun.(), else: :ok
  rescue
    error ->
      Logger.warning("[Brando.Activity] Could not record activity: " <> Exception.message(error))
      :ok
  end

  # A failed insert must not abort the caller's transaction: Postgres refuses
  # every statement after an error until the transaction ends, so inside one
  # the insert runs in a savepoint (Postgrex `mode: :savepoint`) that is rolled
  # back on error, leaving the transaction usable.
  defp insert(attrs) do
    changeset = Ecto.Changeset.change(%Event{}, Map.merge(Process.get(@proposal_key) || %{}, attrs))
    opts = if Repo.repo().in_transaction?(), do: [mode: :savepoint], else: []
    safe_insert(changeset, opts)
  end

  defp safe_insert(changeset, opts) do
    case Repo.insert(changeset, opts) do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        Logger.warning("[Brando.Activity] Could not record activity: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  rescue
    error ->
      Logger.warning("[Brando.Activity] Could not record activity: " <> Exception.message(error))
      {:error, error}
  end

  @doc "The names of the fields a changeset changed, leaving out bookkeeping. Block fields go by their field name."
  def changed_fields(%Ecto.Changeset{changes: changes}) do
    changes
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 in @ignored_fields or String.starts_with?(&1, "rendered")))
    |> Enum.map(&field_name/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp field_name("entry_" <> name), do: name
  defp field_name(name), do: name

  defp status_details(from, entry) do
    case Map.get(entry, :status) do
      nil -> %{}
      to when is_nil(from) -> %{"status" => %{"to" => to_string(to)}}
      to -> %{"status" => %{"from" => to_string(from), "to" => to_string(to)}}
    end
  end

  defp source_details, do: Process.get(@source_details_key) || %{}

  defp source(user) do
    case Process.get(@source_key) do
      nil -> if user in [nil, :system], do: :system, else: :admin
      source -> source
    end
  end

  defp user_id(%Brando.Users.User{id: id}), do: id
  defp user_id(%Scope{user_id: id}), do: id
  defp user_id(_), do: nil

  # The entry's name without touching the database: generating its identifier
  # can query (base context, cover preloads), and a failed query would abort
  # the caller's transaction. The fields its identifier template names come
  # first (`{{ entry.title }}`), then the usual name fields.
  defp title(%{__struct__: schema} = entry) do
    identifier_fields =
      if function_exported?(schema, :__identifier_fields__, 0),
        do: Enum.flat_map(schema.__identifier_fields__(), &existing_field(schema, &1)),
        else: []

    fields = schema.__schema__(:fields)

    Enum.find_value(identifier_fields ++ [:title, :name, :key, :email], fn field ->
      if field in fields, do: present(Map.get(entry, field))
    end) || "##{entry.id}"
  end

  defp existing_field(schema, name) do
    case Enum.find(schema.__schema__(:fields), &(to_string(&1) == name)) do
      nil -> []
      field -> [field]
    end
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil

  defp language(entry) do
    case Map.get(entry, :language) do
      nil -> nil
      language -> to_string(language)
    end
  end

  ## Reading

  @doc """
  Events, newest first. Filters: `:user_id`, `:schema` (module or string),
  `:action`, `:since` (`DateTime`), `:q` (title search), `:schema_in` (the
  schemas the reader may see), `:actor` (a kind, see `actor_kind/1`),
  `:client` (an MCP client's name) and `:proposal_id`. Options: `:limit`
  (default 50), `:offset`.
  """
  def list(filters \\ %{}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    filters
    |> query()
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^limit)
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload([:approver, user: :avatar])
    |> Repo.all()
  end

  @doc "How many events match `filters` (see `list/2`)."
  def count(filters \\ %{}), do: filters |> query() |> Repo.aggregate(:count)

  defp query(filters) do
    Enum.reduce(filters, from(e in Event), fn
      {_key, nil}, query -> query
      {_key, ""}, query -> query
      {:user_id, id}, query -> where(query, [e], e.user_id == ^id)
      {:schema, schema}, query -> where(query, [e], e.schema == ^to_string(schema))
      {:schema_in, schemas}, query -> where(query, [e], e.schema in ^Enum.map(schemas, &to_string/1))
      {:action, action}, query -> where(query, [e], e.action == ^action)
      {:since, since}, query -> where(query, [e], e.inserted_at >= ^since)
      {:entry_id, id}, query -> where(query, [e], e.entry_id == ^id)
      {:actor, kind}, query when kind in @actor_kinds -> where(query, [e], e.source in ^kind_sources(kind))
      {:client, client}, query -> where(query, [e], e.source == :mcp and fragment("?->>'client'", e.details) == ^client)
      {:proposal_id, id}, query -> where(query, [e], e.proposal_id == ^id)
      {:q, q}, query -> where(query, [e], ilike(e.title, ^"%#{Brando.Query.sanitize_ilike_pattern(q)}%"))
      _, query -> query
    end)
  end

  @doc "An entry's events, newest first. Options as for `list/2`."
  def for_entry(schema, entry_id, opts \\ []) do
    list(%{schema: schema, entry_id: entry_id}, opts)
  end

  @doc "Who moved each of `ids` (entries of `schema`) to the trash, as `%{id => user}`, from the latest such event."
  def trashed_by(_schema, []), do: %{}

  def trashed_by(schema, ids) do
    from(e in Event,
      where: e.schema == ^to_string(schema) and e.entry_id in ^ids and e.action == :trashed and not is_nil(e.user_id),
      distinct: e.entry_id,
      order_by: [asc: e.entry_id, desc: e.inserted_at],
      preload: [user: :avatar]
    )
    |> Repo.all()
    |> Map.new(&{&1.entry_id, &1.user})
  rescue
    _ -> %{}
  end

  @doc "The users who appear in the log, for filtering."
  def users do
    from(u in Brando.Users.User,
      where: u.id in subquery(from(e in Event, where: not is_nil(e.user_id), distinct: true, select: e.user_id)),
      order_by: u.name
    )
    |> Repo.all()
  end

  @doc "The names of the tools connected over MCP that appear in the log, for filtering."
  def clients do
    from(e in Event,
      where: e.source == :mcp and not is_nil(fragment("?->>'client'", e.details)),
      distinct: true,
      select: fragment("?->>'client'", e.details)
    )
    |> Repo.all()
    |> Enum.sort()
  end

  @doc "The schemas that appear in the log, for filtering."
  def schemas do
    from(e in Event, distinct: true, select: e.schema, order_by: e.schema)
    |> Repo.all()
    |> Enum.flat_map(fn name ->
      case Brando.Authorization.Catalog.schema(name) do
        nil -> []
        schema -> [schema]
      end
    end)
  end

  @doc "Remove events older than the retention period. Returns how many."
  def purge(days \\ retention_days()) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    {count, _} = Repo.delete_all(from(e in Event, where: e.inserted_at < ^cutoff))
    count
  end
end
