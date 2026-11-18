defmodule Brando.Translations.SharedGalleries do
  @moduledoc """
  The gallery records a translation shares with other versions of its group.

  A synchronized translation shows the source's media. For a gallery variable
  (in a block, a table row or among the entry's own variables)
  `Brando.Translations.Sync` gives the translation the source's `gallery_id`:
  both point at one gallery record. So does a gallery ref that a source save
  added after the translation was created, and a gallery asset when the
  pending version is saved outside the admin form (the form keeps the asset's
  own record and copies its contents). While the translation follows the
  source that is the point: its media is the source's.

  An independent translation keeps its content but no longer follows, so it
  must not keep a record another version uses: an edit there would change the
  source and every other translation. `split/3` gives each such holder its own
  copy (`Brando.Galleries.duplicate_gallery/2`: the same media in the same
  order, with each object's own `config`). Captions and alt text a gallery ref
  keeps in its data are keyed by media, so they stay valid on the copy.

  A holder is `{schema, id, field, gallery_id}`: the row that points at the
  gallery and its foreign key column.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Relations
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Doctor.Context
  alias Brando.Galleries.Gallery
  alias Brando.Repo
  alias Brando.Translations.Member

  @type holder :: {module(), integer(), atom(), integer()}

  @doc """
  The rows of `entry` that point at a gallery: its gallery assets, the gallery
  refs and variables of its blocks (at any depth, table rows included), its own
  variables, and the same in the rows of its owned subforms. `entry` is loaded
  with `Brando.Blueprint.preloads_for/1`.
  """
  @spec holders(struct()) :: [holder()]
  def holders(%module{} = entry) do
    asset_holders(entry, module) ++
      Enum.flat_map(block_joins(entry, module), &block_holders(&1.block)) ++
      Enum.flat_map(var_relations(module), &var_holders(Map.get(entry, &1))) ++
      Enum.flat_map(owned_rows(entry, module), &holders/1)
  end

  @doc """
  The holders of `entry` whose gallery one of `others` (the other versions of
  its group, loaded the same way) points at too.
  """
  @spec shared(struct(), [struct()]) :: [holder()]
  def shared(entry, others) do
    taken = for other <- others, {_, _, _, gallery_id} <- holders(other), into: MapSet.new(), do: gallery_id
    shared = Enum.filter(holders(entry), fn {_, _, _, gallery_id} -> MapSet.member?(taken, gallery_id) end)
    live = live_galleries(Enum.map(shared, &elem(&1, 3)))
    Enum.filter(shared, fn {_, _, _, gallery_id} -> MapSet.member?(live, gallery_id) end)
  end

  # A gallery in the trash is not copied: it shows nowhere, and restored it
  # is the source's again
  defp live_galleries([]), do: MapSet.new()

  defp live_galleries(ids) do
    from(g in Gallery, where: g.id in ^Enum.uniq(ids) and is_nil(g.deleted_at), select: g.id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Gives every holder of `entry` that shares a gallery with `others` a copy of
  it, one copy per holder: a gallery belongs to the row that points at it.
  Returns each holder with its copy: `{:ok, [{holder, %Gallery{}}]}`. A
  gallery in the trash, or gone, is left as it is.

  Run it in a transaction: a failed copy leaves earlier holders pointing at
  theirs.
  """
  @spec split(struct(), [struct()], term()) :: {:ok, [{holder(), struct()}]} | {:error, term()}
  def split(entry, others, actor) do
    entry
    |> shared(others)
    |> Enum.reduce_while({:ok, []}, fn {_, _, _, gallery_id} = holder, {:ok, copies} ->
      case Brando.Galleries.duplicate_gallery(gallery_id, actor) do
        {:ok, copy} ->
          repoint(holder, copy.id)
          {:cont, {:ok, [{holder, copy} | copies]}}

        {:error, reason} ->
          {:halt, {:error, {:gallery, gallery_id, reason}}}
      end
    end)
    |> case do
      {:ok, copies} -> {:ok, Enum.reverse(copies)}
      error -> error
    end
  end

  @doc """
  The independent translations of the current prefix that share a gallery
  with another version of their group, as `{schema, entry_id, language}`.
  """
  @spec independent_sharing() :: [{module(), integer(), String.t()}]
  def independent_sharing do
    members =
      Repo.all(from(m in Member, where: m.role == :target and m.synchronized == false, order_by: [asc: m.id]))

    for %Member{entry_type: type, entry_id: id, language: language} <- members,
        schema = Brando.Blueprint.from_name(type),
        schema != nil,
        Brando.Translations.shared_galleries(schema, id) != [],
        do: {schema, id, language}
  end

  @doc """
  Repairs every independent translation that still shares a gallery with
  another version of its group (the doctor's "Translation galleries"):
  `Brando.Translations.split_shared_galleries/3` for each, as `:system`. With
  tenancy it covers every environment of every active site. Prints a line per
  translation and returns `{:ok, count}` or `{:error, failed}`.

  `mix brando.translations.split_galleries` runs it; in a release,
  `bin/my_app rpc "Brando.Translations.SharedGalleries.repair()"`.
  """
  @spec repair() :: {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  def repair do
    results =
      [mode: :mix]
      |> Context.new()
      |> Context.each_environment(fn ->
        for {schema, id, language} <- independent_sharing(),
            do: {schema, id, language, Brando.Translations.split_shared_galleries(schema, id, :system)}
      end)

    for {label, found} <- results, {schema, id, language, result} <- found do
      name = Context.label_item(label, "#{inspect(schema)} ##{id} (#{language})")

      case result do
        {:ok, copies} -> IO.puts("#{name}: #{length(copies)} gallery copies")
        {:error, reason} -> IO.puts("#{name}: failed, #{inspect(reason)}")
      end
    end

    all = Enum.flat_map(results, &elem(&1, 1))

    case Enum.count(all, &match?({_, _, _, {:error, _}}, &1)) do
      0 -> {:ok, length(all)}
      failed -> {:error, failed}
    end
  end

  defp repoint({schema, id, field, _gallery_id}, gallery_id),
    do: Repo.update_all(from(r in schema, where: r.id == ^id), set: [{field, gallery_id}])

  defp asset_holders(%{id: id} = entry, module) when not is_nil(id) do
    if Brando.Blueprint.embedded?(module) do
      []
    else
      for %{name: name} <- Assets.__assets__(module, :gallery),
          gallery_id = Map.get(entry, :"#{name}_id"),
          do: {module, id, :"#{name}_id", gallery_id}
    end
  end

  defp asset_holders(_entry, _module), do: []

  defp block_joins(entry, module) do
    if module.has_trait(Brando.Trait.Blocks),
      do: Enum.flat_map(module.__blocks_fields__(), &loaded(Map.get(entry, :"entry_#{&1.name}"))),
      else: []
  end

  defp block_holders(%{} = block) do
    ref_holders(loaded(block.refs)) ++
      var_holders(block.vars) ++
      Enum.flat_map(loaded(block.table_rows), &var_holders(&1.vars)) ++
      Enum.flat_map(loaded(block.children), &block_holders/1)
  end

  defp block_holders(_block), do: []

  defp ref_holders(refs), do: for(%Ref{id: id, gallery_id: g} <- refs, id && g, do: {Ref, id, :gallery_id, g})

  defp var_holders(vars),
    do: for(%Var{id: id, gallery_id: g} <- loaded(vars), id && g, do: {Var, id, :gallery_id, g})

  defp var_relations(module) do
    for %{type: :has_many, name: name, opts: %{module: Var}} <- Relations.__relations__(module), do: name
  end

  # The rows a subform owns (`cast: true`), which a translation copies with
  # their galleries
  defp owned_rows(entry, module) do
    for %{type: type, name: name, opts: opts} <- Relations.__relations__(module),
        type in [:has_many, :has_one],
        Map.get(opts, :cast) == true,
        row_module = opts[:module],
        is_atom(row_module) and row_module not in [Var, :blocks],
        Code.ensure_loaded?(row_module) and Brando.Blueprint.blueprint?(row_module),
        row <- load_rows(Map.get(entry, name), row_module),
        do: row
  end

  # A row's own relations and blocks: the entry's preloads reach one level
  # into its subforms
  defp load_rows(rows, row_module) do
    case loaded(rows) do
      [] -> []
      rows -> Repo.preload(rows, Brando.Blueprint.preloads_for(row_module))
    end
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(nil), do: []
  defp loaded(list) when is_list(list), do: list
  defp loaded(%{} = one), do: [one]
end
