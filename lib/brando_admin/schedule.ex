defmodule BrandoAdmin.Schedule do
  @moduledoc """
  What is planned for entries in a stretch of time, for the dashboard's
  "Expiring soon" panel:

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
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint
  alias Brando.ContentEvents.Event
  alias Brando.Content.Identifier.Queries, as: IdentifierQueries
  alias Brando.Publisher
  alias Brando.Repo
  alias BrandoAdmin.CommandPalette

  @kinds [:publish, :revision, :expire]
  @waiting ~w(scheduled available retryable)

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

  @doc "The content types that can be scheduled: they have `Brando.Trait.ScheduledPublishing` and an admin."
  def schemas do
    :include_brando
    |> Brando.Content.Identifier.Registry.list_persistent_identifier_modules()
    |> Enum.filter(&(&1.has_trait(Brando.Trait.ScheduledPublishing) and function_exported?(&1, :__admin_route__, 2)))
    |> Enum.uniq()
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

  defp found(:revision, schemas, from, to) do
    {:ok, jobs} = Publisher.list_jobs()
    names = Map.new(schemas, &{to_string(&1), &1})

    for %{args: %{"revision" => revision, "schema" => name, "id" => id}} = job <- jobs,
        job.state in @waiting,
        schema = names[name],
        not is_nil(schema),
        not DateTime.before?(job.scheduled_at, from),
        DateTime.before?(job.scheduled_at, to),
        entry = Repo.get(schema, id),
        not is_nil(entry),
        is_nil(Map.get(entry, :deleted_at)),
        do: {:revision, entry, job.scheduled_at, revision}
  end

  defp window(schema, field, statuses, from, to) do
    query =
      from e in schema,
        where: e.status in ^statuses and field(e, ^field) >= ^from and field(e, ^field) < ^to,
        order_by: [asc: field(e, ^field), asc: e.id]

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
