defmodule BrandoAdmin.Schedule do
  @moduledoc """
  What is planned for entries in a stretch of time, for the dashboard's
  "Expiring soon" panel and the calendar (`BrandoAdmin.CalendarLive`):

    * `:publish` — a pending entry's `publish_at`
    * `:revision` — a revision scheduled to be restored and published
    * `:expire` — a published or pending entry's `unpublish_at`

  Only content types with `Brando.Trait.ScheduledPublishing` take part, and a
  user sees only the entries they may read, in the current site and
  environment, filtered as the command palette and the search page filter
  them (`BrandoAdmin.CommandPalette`). Each item says whether the user may
  open the entry (`path`) and move it to another time (`movable?`): publishing
  takes the right to schedule, an expiry or a revision also the right to
  publish.

  `reschedule/3` moves an item, through the same code path as changing the
  date where it is set: the entry's context update for `publish_at` and
  `unpublish_at`, as the entry form saves them, and
  `Brando.Publisher.schedule_revision/5` for a revision, as the revisions
  drawer does.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint
  alias Brando.Content.Identifier.Queries, as: IdentifierQueries
  alias Brando.ContentEvents.Event
  alias Brando.Publisher
  alias Brando.Repo
  alias BrandoAdmin.CommandPalette

  @kinds [:publish, :revision, :expire]

  @type item :: %{
          id: String.t(),
          kind: :publish | :revision | :expire,
          at: DateTime.t(),
          schema: module(),
          entry_id: integer(),
          revision: integer() | nil,
          title: String.t(),
          type: String.t(),
          icon: String.t(),
          language: String.t() | nil,
          status: atom() | nil,
          path: String.t() | nil,
          movable?: boolean()
        }

  @doc """
  The content types that can be scheduled: they have
  `Brando.Trait.ScheduledPublishing`, a status and an admin.
  """
  def schemas do
    :include_brando
    |> Brando.Content.Identifier.Registry.list_persistent_identifier_modules()
    |> Enum.uniq()
    |> Enum.filter(&schedulable?/1)
  end

  defp schedulable?(schema) do
    schema.has_trait(Brando.Trait.ScheduledPublishing) and :status in schema.__schema__(:fields) and
      function_exported?(schema, :__admin_route__, 2)
  end

  @doc """
  The schedulable content types the user may read: `%{key, schema, label,
  icon}`, `key` being the type's public name (`"pages.page"`).
  """
  def types(user) do
    permissions = CommandPalette.permissions(user)

    schemas()
    |> Enum.filter(&CommandPalette.allowed?(permissions, :read, &1))
    |> Enum.map(&%{key: Event.entry_type(&1), schema: &1, label: Blueprint.get_plural(&1), icon: Blueprint.get_icon(&1)})
    |> Enum.reject(&is_nil(&1.key))
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  @doc """
  The items from `from` up to `to` (UTC) the user may read, by time.

  Options: `:schemas`, the content types to look in (every schedulable type
  by default), and `:kinds`, a subset of `[:publish, :revision, :expire]`.
  """
  @spec items(map(), DateTime.t(), DateTime.t(), keyword()) :: [item()]
  def items(user, from, to, opts \\ []) do
    schemas = Keyword.get_lazy(opts, :schemas, &schemas/0)
    kinds = Keyword.get(opts, :kinds, @kinds)

    CommandPalette.in_scope(user, fn ->
      permissions = CommandPalette.permissions(user)

      kinds
      |> Enum.flat_map(&found(&1, schemas, from, to))
      |> Enum.flat_map(&item(&1, permissions))
      |> Enum.sort_by(&{DateTime.to_unix(&1.at), &1.title, &1.id})
    end)
  end

  @doc "The item with `id` the user may read, among those from `from` up to `to`."
  def get(user, id, from, to, opts \\ []), do: user |> items(from, to, opts) |> Enum.find(&(&1.id == id))

  @doc """
  Move `item` to `at` (UTC) as `user`, returning `{:ok, item}` with the new
  time, or `{:error, reason}`: `:forbidden`, `:in_the_past`, `:changed` when
  the item is no longer planned as `item` says (the entry was published,
  unscheduled or moved since it was read), a changeset with the entry's own
  errors (an expiry before publishing), or the publisher's reason for a
  revision.
  """
  def reschedule(user, %{movable?: true} = item, %DateTime{} = at) do
    at = DateTime.truncate(at, :second)

    if DateTime.after?(at, DateTime.utc_now()),
      do: CommandPalette.in_scope(user, fn -> move(user, item, at) end),
      else: {:error, :in_the_past}
  end

  def reschedule(_user, _item, _at), do: {:error, :forbidden}

  # The item as the calendar showed it must still be what is planned: the
  # entry may have been published, unscheduled or moved since, by someone
  # else or by a job, and a move made from the old picture would undo that
  # (a future publish_at takes a published entry offline again).
  defp move(user, %{kind: :revision} = item, at) do
    if current?(item) do
      case Publisher.schedule_revision(item.schema, item.entry_id, item.revision, at, user) do
        {:ok, _job} -> {:ok, %{item | at: at}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :changed}
    end
  end

  defp move(user, %{kind: kind} = item, at) do
    field = if kind == :publish, do: :publish_at, else: :unpublish_at
    schema = item.schema
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    with {:ok, entry} <- apply(context, :"get_#{singular}", [%{matches: %{id: item.entry_id}}]),
         true <- planned?(entry, kind, item.at) || {:error, :changed},
         changeset = schema.changeset(entry, %{field => at}, user, nil, []),
         {:ok, _entry} <- apply(context, :"update_#{singular}", [changeset, user]) do
      {:ok, %{item | at: at}}
    else
      {:error, {_, :not_found}} -> {:error, :changed}
      other -> other
    end
  end

  defp planned?(entry, kind, item_at) do
    {field, statuses} = if kind == :publish, do: {:publish_at, [:pending]}, else: {:unpublish_at, [:published, :pending]}

    with nil <- Map.get(entry, :deleted_at),
         true <- entry.status in statuses,
         %DateTime{} = at <- Map.get(entry, field) do
      DateTime.compare(at, item_at) == :eq
    else
      _ -> false
    end
  end

  # The revision still has its waiting job, at the time shown
  defp current?(item) do
    [kinds: [:revision], from: item.at, to: DateTime.add(item.at, 1)]
    |> Publisher.waiting_jobs()
    |> Enum.any?(
      &(&1.args["schema"] == to_string(item.schema) and &1.args["id"] == item.entry_id and
          &1.args["revision"] == item.revision)
    )
  end

  # What each kind finds, before permissions: `{kind, entry, at, revision}`
  defp found(:publish, schemas, from, to) do
    for schema <- schemas,
        entry <- Repo.all(window(schema, :publish_at, [:pending], from, to)),
        do: {:publish, entry, entry.publish_at, nil}
  end

  defp found(:expire, schemas, from, to) do
    for schema <- schemas,
        entry <- Repo.all(window(schema, :unpublish_at, [:published, :pending], from, to)),
        do: {:expire, entry, entry.unpublish_at, nil}
  end

  # The waiting revision jobs in the window, filtered in the query, and their
  # entries loaded in one query per content type
  defp found(:revision, schemas, from, to) do
    names = Map.new(schemas, &{to_string(&1), &1})

    jobs =
      [kinds: [:revision], from: from, to: to]
      |> Publisher.waiting_jobs()
      |> Enum.filter(&Map.has_key?(names, &1.args["schema"]))

    entries =
      jobs
      |> Enum.group_by(&names[&1.args["schema"]], & &1.args["id"])
      |> Map.new(fn {schema, ids} ->
        {schema, Map.new(Repo.all(live(from(e in schema, where: e.id in ^ids))), &{&1.id, &1})}
      end)

    for %{args: %{"revision" => revision, "schema" => name, "id" => id}} = job <- jobs,
        entry = get_in(entries, [names[name], id]),
        not is_nil(entry),
        do: {:revision, entry, job.scheduled_at, revision}
  end

  defp window(schema, field, statuses, from, to) do
    live(
      from e in schema,
        where: e.status in ^statuses and field(e, ^field) >= ^from and field(e, ^field) < ^to,
        order_by: [asc: field(e, ^field), asc: e.id]
    )
  end

  # Not in the trash
  defp live(%Ecto.Query{from: %{source: {_, schema}}} = query) do
    if :deleted_at in schema.__schema__(:fields),
      do: from(e in query, where: is_nil(e.deleted_at)),
      else: query
  end

  defp item({kind, %{__struct__: schema} = entry, at, revision}, permissions) do
    with true <- CommandPalette.allowed?(permissions, :read, entry),
         %{} = identifier <- IdentifierQueries.identifier_for(entry) do
      editable? = CommandPalette.allowed?(permissions, :update, entry)

      [
        %{
          id:
            Enum.join([kind, Event.entry_type(schema), entry.id] ++ List.wrap(revision), "-") |> String.replace(".", "_"),
          kind: kind,
          at: at,
          schema: schema,
          entry_id: entry.id,
          revision: revision,
          title: present(identifier.title) || gettext("Untitled"),
          type: schema |> Blueprint.get_singular() |> Brando.Utils.humanize(),
          icon: Blueprint.get_icon(schema),
          language: present(Map.get(entry, :language)),
          status: Map.get(entry, :status),
          path: if(editable?, do: schema.__admin_route__(:update, [entry.id])),
          movable?: editable? and movable?(permissions, kind, entry)
        }
      ]
    else
      _ -> []
    end
  end

  defp movable?(permissions, :publish, entry), do: can?(permissions, :schedule, entry)

  defp movable?(permissions, _kind, entry),
    do: can?(permissions, :schedule, entry) and can?(permissions, :publish, entry)

  # Legacy authorization has no separate rights to schedule and publish:
  # editing is enough, as in the entry form.
  defp can?({:legacy, _} = permissions, _action, entry), do: CommandPalette.allowed?(permissions, :update, entry)
  defp can?(permissions, action, entry), do: CommandPalette.allowed?(permissions, action, entry)

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: to_string(value)
end
