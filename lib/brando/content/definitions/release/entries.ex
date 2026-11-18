defmodule Brando.Content.Definitions.Release.Entries do
  @moduledoc """
  The entries that use a release's changed modules, in this environment: the
  entries a release apply re-renders, which Verify renders as a dry run and
  the review screen lists.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Blocks, Identifier, Module}
  alias Brando.Repo

  @type entry :: %{
          key: {module(), integer()},
          schema: module(),
          id: integer(),
          title: String.t(),
          type: String.t(),
          language: String.t() | nil,
          status: atom() | nil,
          url: String.t() | nil,
          admin_url: String.t() | nil,
          modules: [String.t()]
        }

  @doc """
  The module IDs of the trees the definition UIDs name (each module with
  its children), here.
  """
  @spec module_ids([String.t()]) :: %{integer() => String.t()}
  def module_ids(uids) do
    roots = Repo.all(from(m in Module, where: m.uid in ^uids and is_nil(m.deleted_at), select: {m.id, m.uid}))
    descend(Map.new(roots), Map.keys(Map.new(roots)))
  end

  defp descend(found, []), do: found

  defp descend(found, parent_ids) do
    children =
      Repo.all(
        from(m in Module,
          where: m.parent_id in ^parent_ids and is_nil(m.deleted_at) and m.id not in ^Map.keys(found),
          select: {m.id, m.uid}
        )
      )

    descend(Map.merge(found, Map.new(children)), Enum.map(children, &elem(&1, 0)))
  end

  @doc """
  What the admin shows of each entry that holds a block of the modules
  `module_ids` names (`%{id => uid}`): title, type, language, status and
  links, sorted by type and title. `:modules` on each entry lists the UIDs of
  the modules it uses, so a screen can tell which tree it re-renders for.
  """
  @spec list(%{integer() => String.t()}) :: [entry()]
  def list(module_ids) when map_size(module_ids) == 0, do: []

  def list(module_ids) do
    by_entry =
      Enum.reduce(module_ids, %{}, fn {module_id, uid}, acc ->
        module_id
        |> Blocks.list_block_ids_using_module(:local)
        |> Blocks.list_root_block_ids_by_source()
        |> Blocks.list_entry_ids_for_root_blocks_by_source()
        |> Enum.reduce(acc, fn {schema, ids}, acc ->
          Enum.reduce(ids, acc, &Map.update(&2, {schema, &1}, [uid], fn uids -> Enum.uniq([uid | uids]) end))
        end)
      end)

    identifiers = identifiers(Map.keys(by_entry))

    by_entry
    |> Enum.map(fn {{schema, id} = key, uids} -> describe(key, identifiers[key], schema, id, uids) end)
    |> Enum.sort_by(&{&1.type, String.downcase(&1.title), &1.id})
  end

  defp identifiers([]), do: %{}

  # Stored identifiers, and for an entry without one (a schema that doesn't
  # persist them), the identifier its Blueprint makes of the entry
  defp identifiers(keys) do
    stored =
      keys
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {schema, ids} ->
        Repo.all(from(i in Identifier, where: i.schema == ^schema and i.entry_id in ^ids))
      end)
      |> Map.new(&{{&1.schema, &1.entry_id}, &1})

    keys
    |> Enum.reject(&Map.has_key?(stored, &1))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(stored, fn {schema, ids}, acc -> schema |> load(ids) |> Enum.reduce(acc, &put_made/2) end)
  end

  defp put_made(%{__struct__: schema, id: id} = entry, acc) do
    case Brando.Content.Identifier.Queries.identifier_for(entry) do
      %Identifier{} = identifier -> Map.put(acc, {schema, id}, identifier)
      _ -> acc
    end
  end

  defp load(schema, ids) do
    Repo.all(from(e in schema, where: e.id in ^ids))
  rescue
    _ -> []
  end

  defp describe(key, identifier, schema, id, uids) do
    %{
      key: key,
      schema: schema,
      id: id,
      title: (identifier && Identifier.title_text(identifier)) || "##{id}",
      type: type(schema),
      language: identifier && identifier.language && to_string(identifier.language),
      status: identifier && identifier.status,
      url: identifier && identifier.url,
      admin_url: admin_url(schema, id),
      modules: Enum.sort(uids)
    }
  end

  defp type(schema) do
    Brando.Blueprint.get_singular(schema) |> to_string() |> String.capitalize()
  rescue
    _ -> schema |> Elixir.Module.split() |> List.last()
  end

  defp admin_url(schema, id) do
    if function_exported?(schema, :__admin_route__, 2), do: schema.__admin_route__(:update, [id])
  rescue
    _ -> nil
  end

  @doc """
  Counts for a summary: entries, how many are live (published), and how many
  content types.
  """
  @spec counts([entry()]) :: %{entries: non_neg_integer(), live: non_neg_integer(), types: non_neg_integer()}
  def counts(entries) do
    %{
      entries: length(entries),
      live: Enum.count(entries, &(&1.status == :published)),
      types: entries |> Enum.map(& &1.schema) |> Enum.uniq() |> length()
    }
  end
end
