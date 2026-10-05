defmodule Brando.Content.BlockAudit do
  @moduledoc """
  Finds block trees no entry links to, says which of them nothing can bring
  back, and removes those, keeping a copy.

  Removing a block from an entry drops the link and keeps the block, so that
  restoring an older revision can link it again. Revisions are purged after
  a while; the blocks they held are not. Over the years a site collects
  blocks that are reachable from nowhere, and whose media then looks "in
  use" by nothing.

  A tree (a root block and everything under it) is **loose** when no table
  links to any block in it. The linking tables are read from the database:
  every foreign key to `content_blocks` outside a block's own records, so a
  site's own schemas, and anything this module has never heard of, count.

  A loose tree is **removable** only when, as well:

    * no stored revision holds any of its blocks
      (`Brando.Revisions.held_block_ids/0`): restoring that revision needs
      them;
    * no recovery copy (entry draft) mentions any of its blocks;
    * every revision could be read. One unreadable revision means its blocks
      are unknown, and then nothing is removable.

  `remove/2` checks all of this again inside its transaction, with the
  linking tables and the revisions locked, copies each tree's rows to
  `Brando.Content.BlockArchive`, and deletes the root (its records go with
  it). `restore/1` puts a tree back from the archive.
  """

  import Ecto.Query

  alias Brando.Content.BlockArchive
  alias Brando.Repo
  alias Brando.Revisions
  alias Brando.Type.I18nString

  # A block's own records: they point at the block because they belong to it.
  @owned ~w(content_blocks content_refs content_vars content_table_rows content_block_identifiers)
  @excerpt_length 110

  @type tree :: %{
          id: integer(),
          uid: String.t() | nil,
          block_ids: [integer()],
          status: :removable | :held_by_revision | :held_by_draft | :unverifiable,
          held_by: [map()],
          source: String.t(),
          module: String.t() | nil,
          module_svg: String.t() | nil,
          description: String.t() | nil,
          excerpt: String.t() | nil,
          image_ids: [integer()],
          inserted_at: NaiveDateTime.t() | DateTime.t() | nil
        }

  @doc """
  The tables that link to blocks, as `[{table, column}]`: every foreign key to
  `content_blocks` that is not one of a block's own records.
  """
  @spec link_tables() :: [{String.t(), String.t()}]
  def link_tables do
    %{rows: rows} =
      sql!("""
      SELECT cl.relname::text, a.attname::text
      FROM pg_constraint c
      JOIN pg_class cl ON cl.oid = c.conrelid
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
      WHERE c.contype = 'f' AND c.confrelid = to_regclass('content_blocks')
      ORDER BY 1, 2
      """)

    for [table, column] <- rows, table not in @owned, do: {table, column}
  end

  @doc """
  Every loose tree with what is known about it, and what was checked.

      %{
        trees: [tree],
        totals: %{blocks: n, loose_trees: n, loose_blocks: n, removable: n, held: n},
        checked: %{link_tables: [...], revisions: n, undecodable_revisions: n, drafts: n}
      }
  """
  @spec scan() :: map()
  def scan do
    links = link_tables()
    {blocks, loose} = loose_trees(links)

    {held, undecodable} = Revisions.held_block_ids()
    drafts = draft_texts()
    by_id = Map.new(blocks, &{&1.id, &1})
    loose_ids = Enum.flat_map(loose, &elem(&1, 1))
    evidence = evidence(loose_ids)
    modules = modules(Enum.map(loose, fn {root, _} -> root.module_id end))

    trees =
      loose
      |> Enum.map(fn {root, ids} ->
        held_by = ids |> Enum.flat_map(&Map.get(held, &1, [])) |> Enum.uniq()
        uids = ids |> Enum.map(&by_id[&1].uid) |> Enum.reject(&(&1 in [nil, ""]))
        in_draft? = Enum.any?(drafts, fn text -> Enum.any?(uids, &String.contains?(text, &1)) end)

        status =
          cond do
            held_by != [] -> :held_by_revision
            in_draft? -> :held_by_draft
            undecodable > 0 -> :unverifiable
            true -> :removable
          end

        %{
          id: root.id,
          uid: root.uid,
          block_ids: ids,
          status: status,
          held_by: held_by,
          source: source_label(root.source),
          module: get_in(modules, [root.module_id, :name]),
          module_svg: get_in(modules, [root.module_id, :svg]),
          description: root.description,
          excerpt: ids |> Enum.find_value(&Map.get(evidence.excerpts, &1)),
          image_ids: ids |> Enum.flat_map(&Map.get(evidence.images, &1, [])) |> Enum.uniq(),
          inserted_at: root.inserted_at
        }
      end)
      |> Enum.sort_by(&{&1.source, -&1.id})

    %{
      trees: trees,
      totals: %{
        blocks: length(blocks),
        loose_trees: length(trees),
        loose_blocks: length(loose_ids),
        removable: Enum.count(trees, &(&1.status == :removable)),
        held: Enum.count(trees, &(&1.status != :removable))
      },
      checked: %{
        link_tables: Enum.map(links, &elem(&1, 0)),
        revisions: Repo.aggregate(Brando.Revisions.Revision, :count),
        undecodable_revisions: undecodable,
        drafts: length(drafts)
      }
    }
  end

  @doc """
  How many loose trees there are. Only the links are checked, not what holds
  them, so this is cheap enough to show beside a link to the audit.
  """
  @spec count_loose() :: non_neg_integer()
  def count_loose do
    {_blocks, loose} = loose_trees(link_tables())
    length(loose)
  end

  # Every block, and the trees no linking table names a block of, as
  # `{root, ids}`.
  defp loose_trees(links) do
    linked = linked_block_ids(links)

    blocks =
      Repo.all(
        from b in "content_blocks",
          select: %{
            id: b.id,
            parent_id: b.parent_id,
            uid: b.uid,
            source: b.source,
            module_id: b.module_id,
            description: b.description,
            inserted_at: b.inserted_at
          }
      )

    children = Enum.group_by(blocks, & &1.parent_id)

    loose =
      for root <- Map.get(children, nil, []),
          ids = tree_ids(root.id, children),
          not Enum.any?(ids, &MapSet.member?(linked, &1)),
          do: {root, ids}

    {blocks, loose}
  end

  @doc """
  Removes the trees with the root ids `root_ids` that are still removable,
  archiving each first. Ids that no longer qualify are left alone and
  reported: `{:ok, %{removed: n, blocks: n, skipped: [root_id]}}`.
  """
  @spec remove([integer()], map() | nil) :: {:ok, map()} | {:error, term()}
  def remove(root_ids, user \\ nil) when is_list(root_ids) do
    Repo.transaction(fn ->
      # Nothing may link a block, or store a revision holding one, between the
      # check and the delete.
      for {table, _column} <- link_tables(), do: sql!(~s(LOCK TABLE "#{quote_ident(table)}" IN SHARE MODE))
      sql!("LOCK TABLE revisions IN SHARE MODE")

      removable =
        scan().trees
        |> Enum.filter(&(&1.status == :removable and &1.id in root_ids))

      Enum.each(removable, fn tree ->
        Repo.insert!(%BlockArchive{
          root_block_id: tree.id,
          uid: tree.uid,
          block_count: length(tree.block_ids),
          summary: Map.take(tree, [:source, :module, :description, :excerpt]),
          data: rows(tree.block_ids),
          removed_by_id: user && Map.get(user, :id)
        })
      end)

      removed_ids = Enum.map(removable, & &1.id)
      # A root's children, refs, vars, table rows and identifiers go with it.
      Repo.delete_all(from b in "content_blocks", where: b.id in ^removed_ids)

      %{
        removed: length(removable),
        blocks: removable |> Enum.map(&length(&1.block_ids)) |> Enum.sum(),
        skipped: root_ids -- removed_ids
      }
    end)
  end

  @doc "The archived trees, newest first, without their row data."
  @spec list_archive() :: [BlockArchive.t()]
  def list_archive do
    Repo.all(
      from a in BlockArchive,
        order_by: [desc: a.id],
        select: struct(a, [:id, :root_block_id, :uid, :block_count, :summary, :removed_by_id, :inserted_at])
    )
  end

  @doc """
  Puts an archived tree back as it was, ids included, and drops it from the
  archive. It comes back loose, as it was when removed. `{:error, message}`
  when the database refuses, for example because media it used is gone.
  """
  @spec restore(integer()) :: {:ok, integer()} | {:error, term()}
  def restore(archive_id) do
    Repo.transaction(fn ->
      case Repo.get(BlockArchive, archive_id) do
        nil ->
          Repo.rollback(:not_found)

        archive ->
          restore_archive(archive)
      end
    end)
  end

  defp restore_archive(archive) do
    for table <- @owned, do: restore_table(table, Map.get(archive.data, table, []))

    Repo.delete!(archive)
    archive.root_block_id
  end

  defp restore_table(_table, []), do: nil

  defp restore_table(table, records) do
    case sql(
           ~s|INSERT INTO "#{table}" SELECT * FROM jsonb_populate_recordset(null::"#{table}", $1::jsonb)|,
           [records]
         ) do
      {:ok, _} -> :ok
      {:error, error} -> Repo.rollback(Exception.message(error))
    end
  end

  # The rows of a tree, per table, as the database has them. Blocks first:
  # `restore/1` inserts in this order, and everything else points at blocks
  # (vars at table rows too).
  defp rows(block_ids) do
    table = fn sql -> sql!(sql, [block_ids]).rows |> hd() |> hd() end

    %{
      "content_blocks" =>
        table.("SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]') FROM content_blocks t WHERE t.id = ANY($1)"),
      "content_refs" =>
        table.(
          "SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]') FROM content_refs t WHERE t.block_id = ANY($1)"
        ),
      "content_table_rows" =>
        table.(
          "SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]') FROM content_table_rows t WHERE t.block_id = ANY($1)"
        ),
      "content_vars" =>
        table.("""
        SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]') FROM content_vars t
        WHERE t.block_id = ANY($1)
           OR t.table_row_id IN (SELECT r.id FROM content_table_rows r WHERE r.block_id = ANY($1))
        """),
      "content_block_identifiers" =>
        table.(
          "SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]') FROM content_block_identifiers t WHERE t.block_id = ANY($1)"
        )
    }
  end

  # Table and column names come from the catalog (`link_tables/0`), not from
  # input; quoted all the same.
  defp linked_block_ids(links) do
    Enum.reduce(links, MapSet.new(), fn {table, column}, acc ->
      %{rows: rows} =
        sql!(
          ~s(SELECT DISTINCT "#{quote_ident(column)}" FROM "#{quote_ident(table)}" WHERE "#{quote_ident(column)}" IS NOT NULL)
        )

      rows |> List.flatten() |> MapSet.new() |> MapSet.union(acc)
    end)
  end

  # Brando.Repo is the site's Ecto repo behind a facade without raw queries.
  defp sql!(statement, params \\ []),
    do: Ecto.Adapters.SQL.query!(Brando.RuntimeConfig.get(:repo_module), statement, params)

  defp sql(statement, params),
    do: Ecto.Adapters.SQL.query(Brando.RuntimeConfig.get(:repo_module), statement, params)

  defp quote_ident(name), do: String.replace(name, ~s("), ~s(""))

  defp tree_ids(id, children), do: [id | Enum.flat_map(Map.get(children, id, []), &tree_ids(&1.id, children))]

  # Recovery copies, as text to look block uids up in.
  defp draft_texts do
    from(d in Brando.Drafts.EntryDraft, select: d.payload)
    |> Repo.all()
    |> Enum.map(&Jason.encode!/1)
  end

  # What a loose block showed: its first text, and its images.
  defp evidence([]), do: %{excerpts: %{}, images: %{}}

  defp evidence(block_ids) do
    refs =
      Repo.all(
        from r in "content_refs",
          where: r.block_id in ^block_ids,
          order_by: [asc: r.block_id, asc: r.id],
          select: %{block_id: r.block_id, data: r.data, image_id: r.image_id}
      )

    excerpts =
      Enum.reduce(refs, %{}, fn ref, acc ->
        case excerpt(ref.data) do
          nil -> acc
          text -> Map.put_new(acc, ref.block_id, text)
        end
      end)

    images =
      refs
      |> Enum.reject(&is_nil(&1.image_id))
      |> Enum.group_by(& &1.block_id, & &1.image_id)

    %{excerpts: excerpts, images: images}
  end

  defp excerpt(%{"data" => %{} = data}) do
    text = data["text"] || data["html"] || data["code"]

    if is_binary(text) do
      text = text |> String.replace(~r/<[^>]*>/, " ") |> String.replace(~r/\s+/, " ") |> String.trim()
      if text != "", do: String.slice(text, 0, @excerpt_length)
    end
  end

  defp excerpt(_), do: nil

  # %{module_id => %{name:, svg:}}: the name and the sketch (base64) of each module.
  defp modules(module_ids) do
    ids = module_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Map.new(
      Repo.all(from m in Brando.Content.Module, where: m.id in ^ids, select: {m.id, m.name, m.svg}),
      fn {id, name, svg} -> {id, %{name: I18nString.localized(name), svg: svg}} end
    )
  end

  # "Elixir.MyApp.Projects.Project.Blocks" → the owning schema's name ("Project").
  defp source_label(nil), do: "?"

  defp source_label(source) do
    join = Module.concat([source])

    with true <- Code.ensure_loaded?(join) and function_exported?(join, :__schema__, 2),
         %{related: owner} <- join.__schema__(:association, :entry) do
      Brando.Blueprint.get_singular(owner)
    else
      _ -> source |> String.replace_prefix("Elixir.", "")
    end
  rescue
    _ -> String.replace_prefix(source, "Elixir.", "")
  end
end
