defmodule Brando.Content.Transfer.Catalog do
  use Gettext, backend: Brando.Gettext
  @moduledoc "Registered block-field providers and destination matching. No submitted schema names become atoms."
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.{BlockPreloads, Identifier}
  alias Brando.Content.Transfer.{Error, Labels}
  alias Brando.Repo

  def schemas do
    Brando.Authorization.Catalog.schemas()
    |> Enum.filter(&(function_exported?(&1, :__blocks_fields__, 0) && &1.__blocks_fields__() != []))
    |> Enum.sort_by(&Brando.Blueprint.get_plural/1)
  end

  def entry_schemas do
    Brando.Authorization.Catalog.schemas()
    |> Enum.filter(&is_binary(&1.__schema__(:source)))
    |> Enum.filter(
      &(&1 == Brando.Pages.Fragment ||
          (function_exported?(&1, :__has_identifier__, 0) && &1.__has_identifier__() && &1.__persist_identifier__()))
    )
    |> Enum.sort_by(&Brando.Blueprint.get_plural/1)
  end

  def schema!(name) do
    Enum.find(schemas(), &(to_string(&1) == to_string(name))) ||
      Error.fail!(dgettext("content_transfer", "This content type is not registered on this site."))
  end

  def fields(schema) do
    definitions = if function_exported?(schema, :__blocks_fields__, 0), do: schema.__blocks_fields__(), else: []

    Enum.map(definitions, fn field ->
      name = to_string(field.name)
      %{name: name, label: Labels.field(name), association: String.to_existing_atom("entry_" <> name)}
    end)
  end

  def field!(schema, name) do
    Enum.find(fields(schema), &(&1.name == to_string(name))) ||
      Error.fail!(dgettext("content_transfer", "This block field does not exist on the destination."))
  end

  def load!(schema_name, id, actor, action \\ :read, opts \\ []) do
    schema = schema!(schema_name)
    id = id!(id)
    query = from(e in schema, where: e.id == ^id) |> scoped_query(schema, actor, action)
    query = if opts[:lock], do: from(e in query, lock: "FOR UPDATE"), else: query
    entry = Repo.one(query) || Error.fail!(dgettext("content_transfer", "The selected entry is no longer available."))
    if Map.get(entry, :deleted_at), do: Error.fail!(dgettext("content_transfer", "The selected entry has been deleted."))
    authorize!(actor, action, entry)
    Repo.preload(entry, BlockPreloads.for_schema(schema))
  end

  def authorize!(actor, action, subject) do
    if Boundary.authorize(actor, action, subject) != :ok,
      do: Error.fail!(dgettext("content_transfer", "You do not have permission to access this content."))

    :ok
  end

  def search(actor, query \\ "", opts \\ []) do
    action = Keyword.get(opts, :action, :export)

    selected =
      if opts[:schema],
        do: [
          if(opts[:entries], do: Brando.Content.Transfer.EntryCodec.schema!(opts[:schema]), else: schema!(opts[:schema]))
        ],
        else: if(opts[:entries], do: entry_schemas(), else: schemas())

    pattern = "%" <> escape_like(String.slice(query, 0, 150)) <> "%"

    selected
    |> Enum.filter(&(is_nil(opts[:schemas]) || to_string(&1) in opts[:schemas]))
    |> Enum.filter(&(Boundary.authorize(actor, action, &1) == :ok))
    |> Enum.flat_map(fn schema ->
      # Fragments intentionally do not persist identifiers. They have their own
      # provider, including parent/key/language matching hints.
      cond do
        schema == Brando.Pages.Fragment ->
          from(e in schema,
            where: is_nil(e.deleted_at) and (ilike(e.title, ^pattern) or ilike(e.key, ^pattern)),
            order_by: e.id,
            limit: 30
          )
          |> scoped_query(schema, actor, action)
          |> Repo.all()
          |> Enum.filter(&(Boundary.authorize(actor, action, &1) == :ok))
          |> Enum.map(&describe/1)

        not schema.__persist_identifier__() ->
          label_field = Enum.find([:title, :name, :key, :slug], &(&1 in schema.__schema__(:fields))) || :id

          query =
            from(e in schema,
              where: ilike(fragment("CAST(? AS text)", field(e, ^label_field)), ^pattern),
              order_by: e.id,
              limit: 60
            )

          query =
            if :deleted_at in schema.__schema__(:fields), do: from(e in query, where: is_nil(e.deleted_at)), else: query

          query
          |> scoped_query(schema, actor, action)
          |> Repo.all()
          |> Enum.filter(&(Boundary.authorize(actor, action, &1) == :ok))
          |> Enum.map(&describe/1)

        true ->
          allowed = from(e in schema, select: e.id) |> scoped_query(schema, actor, action)

          from(i in Identifier,
            where: i.schema == ^schema and ilike(i.title, ^pattern) and i.entry_id in subquery(allowed),
            order_by: [asc: i.title, asc: i.id],
            limit: 60
          )
          |> Repo.all()
          |> Enum.flat_map(fn identifier ->
            case Repo.get(schema, identifier.entry_id) do
              %{deleted_at: deleted} when not is_nil(deleted) -> []
              nil -> []
              entry -> if Boundary.authorize(actor, action, entry) == :ok, do: [describe(entry, identifier)], else: []
            end
          end)
      end
    end)
    |> Enum.sort_by(&{&1.title, &1.schema, &1.id})
    |> Enum.take(60)
    |> with_authors()
  end

  def describe(entry, identifier \\ nil) do
    schema = entry.__struct__
    identifier = identifier || Repo.get_by(Identifier, schema: schema, entry_id: entry.id)

    title =
      (identifier && identifier.title) || Map.get(entry, :title) || Map.get(entry, :name) ||
        "#{Brando.Blueprint.get_singular(schema)} ##{entry.id}"

    title =
      if is_map(title),
        do: title[to_string(Map.get(entry, :language) || "en")] || List.first(Map.values(title)) || "Untitled",
        else: to_string(title)

    %{
      id: entry.id,
      key: "#{schema}:#{entry.id}",
      schema: to_string(schema),
      type: Brando.Content.Transfer.Labels.schema(schema),
      title: title,
      language: to_string(Map.get(entry, :language) || ""),
      status: to_string(Map.get(entry, :status) || ""),
      creator_id: Map.get(entry, :creator_id),
      updated_at: Map.get(entry, :updated_at) || Map.get(entry, :inserted_at),
      url: (identifier && identifier.url) || "",
      hints: hints(entry),
      fields: fields(schema)
    }
  end

  defp with_authors(entries) do
    ids = entries |> Enum.map(& &1.creator_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    names =
      if ids == [],
        do: %{},
        else: Map.new(Repo.all(from(u in Brando.Users.User, where: u.id in ^ids, select: {u.id, u.name})))

    Enum.map(entries, &Map.put(&1, :creator_name, names[&1.creator_id]))
  end

  def hints(%{__struct__: Brando.Pages.Page} = entry), do: %{"uri" => entry.uri, "language" => to_string(entry.language)}

  def hints(%{__struct__: Brando.Pages.Fragment} = entry),
    do: %{"parent_key" => entry.parent_key, "key" => entry.key, "language" => to_string(entry.language)}

  def hints(%{__struct__: schema} = entry) do
    if function_exported?(schema, :content_transfer_key, 1),
      do: schema.content_transfer_key(entry),
      else: %{}
  end

  def candidates(source, actor, action \\ :update) do
    schema =
      Brando.Authorization.Catalog.schema(source["schema"]) ||
        Error.fail!(dgettext("content_transfer", "This content type is not registered on this site."))

    hints = source["hints"] || %{}

    if map_size(hints) == 0 do
      []
    else
      candidate_query(schema, hints)
      |> scoped_query(schema, actor, action)
      |> Repo.all()
      |> Enum.filter(
        &(is_nil(Map.get(&1, :deleted_at)) && hints(&1) == hints && Boundary.authorize(actor, action, &1) == :ok)
      )
      |> Enum.map(&describe/1)
    end
  end

  defp candidate_query(Brando.Pages.Page = schema, hints),
    do: from(e in schema, where: e.uri == ^hints["uri"] and e.language == ^hints["language"])

  defp candidate_query(Brando.Pages.Fragment = schema, hints),
    do:
      from(e in schema,
        where: e.parent_key == ^hints["parent_key"] and e.key == ^hints["key"] and e.language == ^hints["language"]
      )

  defp candidate_query(schema, hints) do
    if function_exported?(schema, :content_transfer_query, 1), do: schema.content_transfer_query(hints), else: schema
  end

  def scoped_query(query, schema, actor, action) do
    if Brando.Authorization.Engine.enabled?(),
      do: Brando.Authorization.Engine.scope_query(Boundary.actor_scope(actor), action, query, schema),
      else: query
  end

  def id!(id) when is_integer(id) and id > 0, do: id

  def id!(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> number
      _ -> Error.fail!(dgettext("content_transfer", "Choose a destination record."))
    end
  end

  def id!(_), do: Error.fail!(dgettext("content_transfer", "Choose a destination record."))

  defp escape_like(query),
    do: query |> String.replace("\\", "\\\\") |> String.replace("%", "\\%") |> String.replace("_", "\\_")
end
