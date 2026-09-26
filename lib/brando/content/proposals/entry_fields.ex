defmodule Brando.Content.Proposals.EntryFields do
  @moduledoc """
  Entry fields a proposal sets beyond plain values: media fields, and lists.

  A list is either a join relation an editor fills with a multi select — a
  case's categories, rows of `ProjectCategory` pointing at a `Category` — set
  as the related records' ids, or an `:entries` relation, set as entries
  (`{:entry, schema, id}`) and saved through their identifiers. Either list
  is replaced as a whole, in the order given.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Content
  alias Brando.Content.Transfer.{Catalog, Error}
  alias Brando.Repo

  @type list_field :: {:join, atom(), module(), module()} | {:entries, module()}

  @doc "The list fields of `schema`, by name."
  @spec lists(module()) :: %{String.t() => list_field()}
  def lists(schema) do
    for relation <- Brando.Blueprint.Relations.__relations__(schema), list = list_field(schema, relation), into: %{} do
      {to_string(relation.name), list}
    end
  rescue
    _ -> %{}
  end

  defp list_field(_schema, %{type: :entries, opts: %{module: join}}), do: {:entries, join}

  defp list_field(schema, %{type: :has_many, name: name, opts: opts}) do
    with true <- Map.get(opts, :cast, false),
         %{related: join, related_key: owner_key} <- schema.__schema__(:association, name),
         true <- is_atom(join) and function_exported?(join, :__schema__, 1),
         [%{owner_key: key, related: related}] <- picks(join, owner_key) do
      {:join, key, related, join}
    else
      _ -> nil
    end
  end

  defp list_field(_schema, _relation), do: nil

  # The one record a join row points at, besides its owner and bookkeeping.
  defp picks(join, owner_key) do
    for name <- join.__schema__(:associations),
        %Ecto.Association.BelongsTo{} = assoc <- [join.__schema__(:association, name)],
        assoc.owner_key != owner_key,
        assoc.related != Brando.Users.User,
        do: assoc
  end

  @doc """
  Load the lists of `entry` — `names`, or all — so they can be read and
  replaced. An entries list loads its identifiers too.
  """
  @spec preload(struct(), [String.t()] | :all) :: struct()
  def preload(entry, names \\ :all) do
    preloads =
      for {name, list} <- lists(entry.__struct__), names == :all or name in names do
        case list do
          {:entries, _join} -> {String.to_existing_atom(name), :identifier}
          _join -> String.to_existing_atom(name)
        end
      end

    if preloads == [], do: entry, else: Repo.preload(entry, preloads)
  end

  @doc "List fields as `describe_content_type` shows them."
  @spec describe(module()) :: [map()]
  def describe(schema) do
    for {name, list} <- lists(schema) do
      case list do
        {:join, _key, related, _join} ->
          %{name: name, type: "list of #{inspect(related)} ids", required: false}

        {:entries, _join} ->
          %{name: name, type: ~s(list of entries [{"content_type":T,"id":N}]), required: false}
      end
    end
  end

  @doc "Problems with the list and media values in `fields` of `schema`."
  @spec problems(module(), map(), term()) :: [{atom(), String.t()}]
  def problems(schema, fields, actor) do
    lists = lists(schema)

    Enum.flat_map(fields, fn {name, value} ->
      case {Map.get(lists, name), value} do
        {nil, _} -> []
        {_, value} when not is_list(value) -> [{:unsupported_value, "#{name} takes a list."}]
        {{:join, _key, related, _join}, ids} -> ids_problems(name, related, ids)
        {{:entries, _join}, entries} -> entries_problems(name, entries, actor)
      end
    end)
  end

  defp ids_problems(name, related, ids) do
    if Enum.all?(ids, &is_integer/1) do
      unique = Enum.uniq(ids)
      found = Repo.one(from(r in related, where: r.id in ^unique, select: count(r.id)))
      if found == length(unique), do: [], else: [{:unknown_target, "#{name} lists an id that does not exist."}]
    else
      [{:unsupported_value, "#{name} takes ids."}]
    end
  end

  defp entries_problems(name, entries, actor) do
    Enum.flat_map(entries, fn
      {:entry, schema, id} ->
        cond do
          match?({:error, _}, Error.protect(fn -> Catalog.load!(schema, id, actor, :read) end)) ->
            [{:unknown_target, "#{name}: the entry was not found."}]

          match?({:error, _}, Content.get_identifier(schema, %{id: id})) ->
            [{:unsupported_value, "#{name}: the entry has no identifier yet."}]

          true ->
            []
        end

      {:new, _} ->
        []

      _ ->
        [{:unsupported_value, ~s(#{name} takes entries as {"content_type", "id"}.)}]
    end)
  end

  @doc """
  Changeset params for `fields`: media as their ids, lists as the rows of
  their join schema.
  """
  @spec params(module(), map()) :: map()
  def params(schema, fields) do
    lists = lists(schema)

    Map.new(fields, fn {name, value} ->
      case {Map.get(lists, name), value} do
        {nil, {kind, id}} when kind in [:image, :video, :file] -> {name, id}
        {nil, value} -> {name, value}
        {{:join, key, _related, join}, ids} -> {name, rows(join, Enum.map(ids, &%{to_string(key) => &1}))}
        {{:entries, join}, entries} -> {name, rows(join, Enum.map(entries, &%{"identifier_id" => identifier_id(&1)}))}
      end
    end)
  end

  defp rows(join, rows) do
    if :sequence in join.__schema__(:fields),
      do: rows |> Enum.with_index() |> Enum.map(fn {row, index} -> Map.put(row, "sequence", index) end),
      else: rows
  end

  defp identifier_id({:entry, schema, id}) do
    {:ok, identifier} = Content.get_identifier(schema, %{id: id})
    identifier.id
  end

  @doc "A list value as the reviewer reads it: titles, in order."
  @spec display(module(), String.t(), term()) :: String.t() | nil
  def display(schema, name, value) when is_list(value) do
    case Map.get(lists(schema), name) do
      {:join, _key, related, _join} ->
        titles = Map.new(Repo.all(from(r in related, where: r.id in ^value)), &{&1.id, title(&1)})
        Enum.map_join(value, ", ", &Map.get(titles, &1, "##{&1}"))

      {:entries, _join} ->
        Enum.map_join(value, ", ", fn
          {:entry, schema, id} ->
            case Content.get_identifier(schema, %{id: id}) do
              {:ok, %{title: title}} -> title
              _ -> "##{id}"
            end

          other ->
            inspect(other)
        end)

      nil ->
        nil
    end
  rescue
    _ -> nil
  end

  def display(_schema, _name, _value), do: nil

  @doc "A saved list, as the reviewer reads it."
  @spec current(struct(), String.t()) :: String.t() | nil
  def current(entry, name) do
    case {Map.get(lists(entry.__struct__), name), Map.get(entry, String.to_existing_atom(name))} do
      {{:join, key, _related, _}, rows} when is_list(rows) ->
        display(entry.__struct__, name, Enum.map(rows, &Map.get(&1, key)))

      {{:entries, _}, rows} when is_list(rows) ->
        rows
        |> Enum.map(&Map.get(&1, :identifier))
        |> Enum.map_join(", ", &((&1 && Map.get(&1, :title)) || "?"))

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp title(record), do: Map.get(record, :title) || Map.get(record, :name) || "##{record.id}"
end
