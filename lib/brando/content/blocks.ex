defmodule Brando.Content.Blocks do
  @moduledoc """
  Block queries, cascade orchestration, entry rendering,
  module sync, and struct manipulation.

  Extracted from `Brando.Villain` to establish a clean boundary:
  Content owns data and orchestration, Villain owns rendering.
  """
  use Brando.Tracing.Decorator

  import Ecto.Query

  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.BlockPreloads
  alias Brando.Content.Module, as: ContentModule
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Content.Var.FollowLinkDefault
  alias Brando.Repo
  alias Brando.RichText
  alias Brando.Tracing
  alias Brando.Trait
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.Blocks, as: VillainBlocks
  alias Brando.Villain.Blocks.MediaBlock
  alias Ecto.Changeset

  @type changeset :: Ecto.Changeset.t()
  @fragment_module Module.concat(["Brando", "Pages", "Fragment"])
  # Renders of an entry that each lost to a write before `render_entry/2` gives up
  @render_attempts 5

  # --- Block Construction ---

  @doc """
  Build an insert changeset for a new block from a module definition.

  `module_reference` is a module id or a shared-library reference. Refs get
  fresh UIDs and vars are copied without primary keys, so the block owns its
  own rows. The block is stamped with the module's current version: a block
  built from the definition as it stands has nothing to migrate.
  """
  @spec build_module_block(term(), integer() | nil, integer() | nil, module(), atom()) :: changeset
  def build_module_block(module_reference, user_id, parent_id, source, type) do
    {module_origin, module_id} = Content.SharedLibrary.reference(module_reference)
    module = Content.fetch_module(module_id, module_origin)

    refs =
      (module.refs || [])
      |> remove_pk_from_refs()
      |> Enum.map(fn ref ->
        %Ref{
          name: ref.name,
          description: ref.description,
          data: ref.data,
          sequence: ref.sequence,
          uid: Utils.generate_uid()
        }
      end)

    %Block{}
    |> Changeset.change(%{
      uid: Utils.generate_uid(),
      type: type,
      creator_id: user_id,
      module_id: module_id,
      module_origin: module_origin,
      module_version: module.version || 1,
      parent_id: parent_id,
      multi: module.multi,
      source: source,
      children: [],
      block_identifiers: [],
      table_rows: []
    })
    |> Changeset.put_assoc(:vars, remove_pk_from_vars(module.vars))
    |> Changeset.put_assoc(:refs, refs)
    |> Map.put(:action, :insert)
  end

  @doc """
  A block of the module `module_reference` for a file dropped on a multi
  block (the parent module's `media_drop`), built as `build_module_block/5`
  builds a `:module_entry`. Its ref `ref_name` takes the file's `kind`
  (`:image` or `:video`): a `:media` ref becomes a picture or a video ref,
  with the ref's template for it (`MediaBlock.typed/2`) or the type's empty
  data; a `:picture` or `:video` ref stays as it is.
  """
  @spec build_media_drop_block(term(), String.t(), :image | :video, integer() | nil, module()) :: changeset
  def build_media_drop_block(module_reference, ref_name, kind, user_id, source) do
    block_cs = build_module_block(module_reference, user_id, nil, source, :module_entry)

    refs =
      block_cs
      |> Changeset.get_assoc(:refs, :struct)
      |> Enum.map(fn
        %Ref{name: ^ref_name, data: %MediaBlock{data: data}} = ref ->
          %{ref | data: with_data(MediaBlock.typed(data, if(kind == :video, do: "video", else: "picture")))}

        ref ->
          ref
      end)

    Changeset.put_assoc(block_cs, :refs, refs)
  end

  # A block built here, not cast from a form, has its type's empty data
  # where the ref has no template for it: its field renders from the data
  defp with_data(%{data: nil} = block), do: %{block | data: struct(Module.concat(block.__struct__, Data))}
  defp with_data(block), do: block

  @doc """
  Render every block field of an entry changeset into its `rendered_*` columns.

  The generated `create_*`/`update_*` mutations save what they are given; the
  admin form renders before calling them, and so must any other writer that
  changes blocks.

  The `rendered_*_at` columns are always written, even with the value they
  had, so the save writes the entry's row: a background render that loaded
  the entry before the save sees that and renders again (`render_entry/2`).
  A writer that renders outside the entry's row lock also stores with
  `store_fenced/3`.

  When a block template fails (`render_fields/3`), no `rendered_*` column is
  changed: the entry keeps the HTML it had, the rest of the changeset saves,
  and the failure is logged.
  """
  @spec render_block_fields(changeset) :: changeset
  @decorate span("brando.blocks.render_fields", schema: :schema, entry_id: [:changeset, :data, :id])
  def render_block_fields(%Changeset{data: %{__struct__: schema}} = changeset) do
    fields = schema.__blocks_fields__()
    Tracing.set_attributes(%{"brando.field_count": length(fields)})

    dropped =
      Enum.flat_map(fields, &[&1.name, :"entry_#{&1.name}", :"rendered_#{&1.name}", :"rendered_#{&1.name}_at"])

    entry = changeset |> Changeset.apply_changes() |> Map.drop(dropped)

    fields
    |> Enum.map(&{&1.name, changeset |> Changeset.get_assoc(:"entry_#{&1.name}") |> Utils.apply_changes_recursively()})
    |> render_field_blocks(entry)
    |> case do
      {:ok, rendered} ->
        put_rendered(changeset, rendered, :always)

      {:error, {:render_failed, failures}} ->
        log_render_failure(schema, changeset.data.id, failures)
        changeset
    end
  end

  @doc """
  Renders every block field of `entry` without storing anything. `entry` is
  loaded with its blocks, as `Brando.Blueprint.EntryQuery.get/2` loads it.

  Returns `{:ok, %{field_name => html}}`, or
  `{:error, {:render_failed, failures}}` when a block template in any field
  failed: a `Brando.Villain.RenderFailure` for each block, with its field.
  `opts` go to `Brando.Villain.parse_checked/3`.

  The stored render (`render_entry/2`) is this, then the store.
  """
  @spec render_fields(module, map, keyword) ::
          {:ok, %{atom => String.t()}} | {:error, {:render_failed, [Brando.Villain.RenderFailure.t()]}}
  def render_fields(schema, entry, opts \\ []) do
    schema.__blocks_fields__()
    |> Enum.map(&{&1.name, Map.get(entry, :"entry_#{&1.name}")})
    |> render_field_blocks(entry, opts)
  end

  @doc """
  `render_fields/3` for blocks given apart from the entry: `fields` is
  `[{field_name, entry_blocks}]`, as the admin form renders the blocks its
  block fields hold rather than the entry's.
  """
  @spec render_field_blocks([{atom, term}], map, keyword) ::
          {:ok, %{atom => String.t()}} | {:error, {:render_failed, [Brando.Villain.RenderFailure.t()]}}
  def render_field_blocks(fields, entry, opts \\ []) do
    {rendered, failures} =
      Enum.reduce(fields, {%{}, []}, fn {name, blocks}, {rendered, failures} ->
        case Villain.parse_checked(blocks, entry, opts) do
          {:ok, html} -> {Map.put(rendered, name, html), failures}
          {:error, failed} -> {rendered, failures ++ Enum.map(failed, &%{&1 | field: name})}
        end
      end)

    if failures == [], do: {:ok, rendered}, else: {:error, {:render_failed, failures}}
  end

  # Each `rendered_*_at` is written `:always`, or `:if_changed`: when its HTML is
  defp put_rendered(changeset, rendered, stamp) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Enum.reduce(rendered, changeset, fn {name, html}, acc ->
      acc = Changeset.put_change(acc, :"rendered_#{name}", html)

      cond do
        stamp == :always -> Changeset.force_change(acc, :"rendered_#{name}_at", now)
        Changeset.get_change(acc, :"rendered_#{name}") -> Changeset.put_change(acc, :"rendered_#{name}_at", now)
        true -> acc
      end
    end)
  end

  @doc """
  Logs, at error level, that a render of the entry `id` of `schema` was not
  stored, and each failure. Called once per render, by whichever caller gave
  up storing it.
  """
  @spec log_render_failure(module, term, [Brando.Villain.RenderFailure.t()]) :: :ok
  def log_render_failure(schema, id, failures) do
    require Logger

    Logger.error("""
    ==> Rendering #{inspect(schema)} #{inspect(id)} failed: its stored HTML is kept

    #{Enum.map_join(failures, "\n", &("  * " <> Brando.Villain.RenderFailure.describe(&1)))}
    """)
  end

  # --- Block Queries ---

  @doc """
  List all registered :blocks fields
  """
  @spec list_blocks :: [module()]
  def list_blocks do
    blocks_blueprint_impls = Trait.Blocks.list_implementations()
    legacy_blueprint_impls = Trait.Villain.list_implementations()
    blueprint_impls = Enum.uniq(blocks_blueprint_impls ++ legacy_blueprint_impls)
    Enum.map(blueprint_impls, &{&1, &1.__blocks_fields__()})
  end

  @doc """
  Return block module corresponding to `block_type`.
  Used when creating refs in ModuleFormLive.
  """
  def get_block_by_type(block_type) do
    default_blocks = VillainBlocks.list_blocks()
    Keyword.get(default_blocks, block_type)
  end

  @doc """
  List all entries with blocks using modules
  """
  def list_module_usage do
    {:ok, module_ids} = Content.list_modules(%{select: [:id], with_deleted: false})

    Enum.map(module_ids, fn %{id: module_id} ->
      module_id
      |> list_block_ids_using_module()
      |> list_root_block_ids_by_source()
      |> list_entry_ids_for_root_blocks_by_source()
    end)
  end

  @doc """
  List all entries with blocks a module is used in
  """
  def list_module_usage(module_id) do
    module_id
    |> list_block_ids_using_module()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
  end

  @doc """
  List all unused modules
  """
  def list_unused_modules do
    query =
      from m in Content.Module,
        left_join: b in Block,
        on: b.module_id == m.id,
        where: is_nil(b.id) and is_nil(m.deleted_at),
        order_by: [asc: m.namespace, asc: m.name],
        select: m

    query
    |> Repo.all()
    |> Enum.map(&%{name: &1.name, namespace: &1.namespace, id: &1.id})
  end

  @doc """
  Lists root blocks no entry links to any more.

  A block is reachable only through the join schema named in its `source`, and
  only at the root: nested blocks hang off `parent_id` and are owned by their
  root, never by a join row of their own. So the check runs per source table,
  over roots only.

  > #### Diagnostic, not a cleanup list {: .warning}
  >
  > These blocks are retained on purpose. Removing a block from an entry drops
  > the join row and keeps the block so that restoring an older revision can
  > re-link it — see `Brando.Revisions.set_entry_to_revision/5`, which aborts the
  > whole restore with `{:missing_block, id}` if the block is gone. Deleting
  > what this returns breaks revision restore for any revision still holding
  > that block, and `protected`/`scheduled` revisions are never purged.
  """
  def list_orphaned_blocks do
    from(b in Block, where: is_nil(b.parent_id), select: %{id: b.id, source: b.source})
    |> Repo.all()
    |> Enum.group_by(& &1.source, & &1.id)
    |> Enum.flat_map(fn {source, ids} -> reject_linked_blocks(source, ids) end)
  end

  # A block whose `source` names no loadable schema has nothing that could link
  # it, so every one of them is unreachable by definition.
  defp reject_linked_blocks(source, ids) do
    case join_table(source) do
      nil ->
        Enum.map(ids, &%{id: &1, source: source})

      table ->
        linked =
          from(j in table, where: j.block_id in ^ids, select: j.block_id)
          |> Repo.all()
          |> MapSet.new()

        ids
        |> Enum.reject(&MapSet.member?(linked, &1))
        |> Enum.map(&%{id: &1, source: source})
    end
  end

  defp join_table(nil), do: nil

  defp join_table(source) do
    schema = Module.concat([source])

    if Code.ensure_loaded?(schema) and function_exported?(schema, :__schema__, 1) do
      schema.__schema__(:source)
    end
  end

  @doc """
  Return list of all blocks using `palette_id`
  """
  def list_block_ids_using_palette(palette_id, origin \\ nil) do
    query =
      from b in Block,
        select: b.id,
        where: b.palette_id == ^palette_id

    query
    |> maybe_filter_library_origin(:palette_origin, origin)
    |> Repo.all()
  end

  @doc "Return list of all blocks using `container_id`."
  def list_block_ids_using_container(container_id, origin \\ nil) do
    query =
      from b in Block,
        select: b.id,
        where: b.container_id == ^container_id

    query
    |> maybe_filter_library_origin(:container_origin, origin)
    |> Repo.all()
  end

  @doc """
  Return list of all block IDs that have a ref using `gallery_id`
  """
  def list_block_ids_using_gallery(gallery_id) do
    query =
      from r in Ref,
        select: r.block_id,
        where: r.gallery_id == ^gallery_id and not is_nil(r.block_id)

    Repo.all(query)
  end

  @doc """
  Return list of all blocks showing `video_id`: in a ref, a var, or a gallery
  their ref holds
  """
  def list_block_ids_using_video(video_id) do
    in_refs = from r in Ref, select: r.block_id, where: r.video_id == ^video_id and not is_nil(r.block_id)
    in_vars = from v in Var, select: v.block_id, where: v.video_id == ^video_id and not is_nil(v.block_id)

    in_galleries =
      from r in Ref,
        join: o in Brando.Galleries.GalleryObject,
        on: o.gallery_id == r.gallery_id,
        select: r.block_id,
        where: o.video_id == ^video_id and not is_nil(r.block_id)

    [in_refs, in_vars, in_galleries]
    |> Enum.flat_map(&Repo.all/1)
    |> Enum.uniq()
  end

  @doc """
  Return list of all blocks using `identifier_id` through a var: one of the
  block's own, or a cell of one of its table rows.
  """
  def list_block_ids_using_identifier(identifier_id) do
    query =
      from v in Var,
        left_join: row in assoc(v, :table_row),
        where: v.identifier_id == ^identifier_id,
        where: not is_nil(v.block_id) or not is_nil(row.block_id),
        select: coalesce(v.block_id, row.block_id),
        distinct: true

    Repo.all(query)
  end

  @doc """
  Return list of all blocks containing `data-identifier-id="ID"` in ref data (TipTap inline links)
  """
  def list_block_ids_with_identifier_in_refs(identifier_id) do
    from(r in Ref,
      where: not is_nil(r.block_id) and fragment("CAST(? AS TEXT) ILIKE ?", r.data, "%data-identifier-id%")
    )
    |> Repo.all()
    |> Enum.filter(fn ref ->
      case ref.data do
        %{data: %{text: text}} -> RichText.contains_identifier?(text, identifier_id)
        _ -> false
      end
    end)
    |> Enum.map(& &1.block_id)
    |> Enum.uniq()
  end

  @doc """
  Return list of all blocks containing `data-identifier-id="ID"` in an html
  var: one of the block's own, or a cell of one of its table rows.
  """
  def list_block_ids_with_identifier_in_html_vars(identifier_id) do
    from(v in Var,
      left_join: row in assoc(v, :table_row),
      where: v.type == :rich_text and ilike(v.value, "%data-identifier-id%"),
      where: not is_nil(v.block_id) or not is_nil(row.block_id),
      select: {coalesce(v.block_id, row.block_id), v.value}
    )
    |> Repo.all()
    |> Enum.filter(fn {_block_id, html} -> RichText.contains_identifier?(html, identifier_id) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
  end

  @doc """
  Return list of all blocks using `module_id`
  """
  def list_block_ids_using_module(module_id, origin \\ nil) do
    query =
      from b in Block,
        select: b.id,
        where: b.module_id == ^module_id

    query
    |> maybe_filter_library_origin(:module_origin, origin)
    |> Repo.all()
  end

  @doc """
  Return list of all blocks using `fragment_id`
  """
  def list_block_ids_using_fragment(fragment_id) do
    query =
      from b in Block,
        select: b.id,
        where: b.fragment_id == ^fragment_id

    Repo.all(query)
  end

  @doc """
  List ids of `schema` records that has a datasource matching schema OR
  a module containing a datasource matching schema.
  """
  defdelegate list_block_ids_using_datamodule(datasource), to: Brando.Content.BlockReferences

  @doc """
  Lists block ids backed by any module id in `module_ids`.
  """
  defdelegate list_block_ids_using_modules(module_ids), to: Brando.Content.BlockReferences

  @doc """
  Resolves root block ids, grouped by join schema, to owning entry ids.
  """
  defdelegate list_entry_ids_for_root_blocks_by_source(source_map), to: Brando.Content.BlockReferences

  @doc """
  Walks parent links and groups the root ids for `block_ids` by join schema.
  """
  defdelegate list_root_block_ids_by_source(block_ids), to: Brando.Content.BlockReferences

  # A ref whose template a superuser writes: Liquid in it runs in the final pass.
  # What editors write in other refs and in vars prints as text.
  @liquid_ref_types ~w(html svg)

  @doc """
  Lists the ids of blocks whose HTML or SVG refs match a regex of
  `search_terms`. Only these refs hold Liquid that runs; Liquid in other refs
  and in vars prints as text.
  """
  @spec list_block_ids_matching_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def list_block_ids_matching_regex(search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    org_query =
      from(b in Block,
        join: refs in assoc(b, :refs),
        on: fragment("?->>'type'", refs.data) in ^@liquid_ref_types,
        as: :refs,
        select: %{"id" => b.id},
        order_by: [asc: b.id]
      )

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
        from([q, refs: refs] in query,
          select_merge: %{
            ^to_string(search_name) =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(refs.data, :string),
                ^search_term
              )
          }
        )
      end)

    built_query
    |> Repo.all()
    |> Enum.map(& &1["id"])
    |> Enum.uniq()
  end

  @doc """
  Searches all modules' `code` for `search_terms`.

  Search terms should be a keyword list with the key being the name of the
  search and the value being the regex to search for.
  """
  @spec search_modules_for_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def search_modules_for_regex(search_terms) do
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    org_query =
      from(s in Content.Module,
        select: %{"id" => s.id, "namespace" => s.namespace, "name" => s.name}
      )

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
        from(q in query,
          select_merge: %{
            ^to_string(search_name) =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(field(q, :code), :string),
                ^search_term
              )
          }
        )
      end)

    Repo.all(built_query)
  end

  @doc """
  Remove all blocks matching `ids` that belong to `entry`
  """
  defdelegate reject_blocks_belonging_to_entry(ids, entry), to: Brando.Content.BlockReferences

  # --- Cascade Orchestration ---

  @doc """
  Render and update all entries with a block using `module_id`.
  First syncs the module with the block, renders the block,
  then renders all entries using the block.
  """
  def render_entries_with_module_id(module_id, origin \\ :local) do
    module_id
    |> list_block_ids_using_module(origin)
    |> sync_blocks(module_id, origin)
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block using `fragment_id`
  """
  def render_entries_with_fragment_id(fragment_id) do
    fragment_id
    |> list_block_ids_using_fragment()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block using `palette_id`
  """
  def render_entries_with_palette_id(palette_id, origin \\ :local) do
    palette_id
    |> list_block_ids_using_palette(origin)
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc "Render entries containing a block that uses `container_id`."
  def render_entries_with_container_id(container_id, origin \\ :local) do
    container_id
    |> list_block_ids_using_container(origin)
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block using a ref with `gallery_id`
  """
  def render_entries_with_gallery_id(gallery_id) do
    gallery_id
    |> list_block_ids_using_gallery()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Render and update all entries with a block showing `video_id`
  (`list_block_ids_using_video/1`)
  """
  def render_entries_with_video_id(video_id) do
    video_id
    |> list_block_ids_using_video()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Update the href of identifier links in all refs that reference the given identifier.

  A failure is logged and leaves the refs as they were.
  """
  def update_identifier_links_in_refs(identifier_id, new_url) do
    isolate_identifier_link_step("block refs", fn -> rewrite_ref_identifier_links(identifier_id, new_url) end)
  end

  defp rewrite_ref_identifier_links(identifier_id, new_url) do
    search_term = "%data-identifier-id%"

    query =
      from r in Brando.Content.Ref,
        where: fragment("CAST(? AS TEXT) ILIKE ?", r.data, ^search_term)

    refs = Repo.all(query)

    for ref <- refs,
        match?(%{data: %{text: text}} when is_binary(text), ref.data),
        RichText.contains_identifier?(ref.data.data.text, identifier_id) do
      in_holder_transaction(fn -> update_locked_ref_identifier_link(ref.id, identifier_id, new_url) end)
    end
  end

  defp update_locked_ref_identifier_link(ref_id, identifier_id, new_url) do
    # Re-read under a row lock so a URL refresh cannot replace newer wording.
    case Repo.one(from r in Ref, where: r.id == ^ref_id, lock: "FOR UPDATE") do
      nil -> :ok
      current -> update_ref_identifier_link(current, identifier_id, new_url)
    end
  end

  defp update_ref_identifier_link(ref, identifier_id, new_url) do
    data = ref.data

    case data do
      %{data: %{text: text}} when is_binary(text) ->
        case Brando.Villain.update_identifier_url_in_html(text, identifier_id, new_url) do
          {:updated, new_text} ->
            new_inner_data = Map.put(data.data, :text, new_text)
            new_data = Map.put(data, :data, new_inner_data)

            ref
            |> Ecto.Changeset.change(%{data: new_data})
            |> Repo.update()

          :unchanged ->
            :ok
        end

      _ ->
        :ok
    end
  end

  @doc """
  Update the href of identifier links in html vars (block vars and table
  cells) that reference the given identifier.

  A failure is logged and leaves the vars as they were.
  """
  def update_identifier_links_in_html_vars(identifier_id, new_url) do
    isolate_identifier_link_step("rich-text vars", fn -> rewrite_var_identifier_links(identifier_id, new_url) end)
  end

  defp rewrite_var_identifier_links(identifier_id, new_url) do
    query = from v in Var, where: v.type == :rich_text and ilike(v.value, "%data-identifier-id%"), select: {v.id, v.value}

    for {id, html} <- Repo.all(query), RichText.contains_identifier?(html, identifier_id) do
      in_holder_transaction(fn -> update_locked_var_identifier_link(id, identifier_id, new_url) end)
    end
  end

  defp update_locked_var_identifier_link(var_id, identifier_id, new_url) do
    # Re-read under a row lock so a URL refresh cannot replace newer wording.
    with %Var{} = var <- Repo.one(from v in Var, where: v.id == ^var_id, lock: "FOR UPDATE"),
         {:updated, html} <- RichText.update_identifier_url(var.value, identifier_id, new_url) do
      var |> Changeset.change(value: html) |> Repo.update()
    end
  end

  @doc """
  Update identifier link URLs in rich text fields across all schemas.

  Walks `modules` (by default `identifier_link_modules/0`) for the
  `:rich_text` inputs of each of their forms, at the top of the form and in
  subform rows (`rich_text_targets/1`), searches the rows holding them for
  `data-identifier-id="ID"`, and updates the href to the new URL. Only rows
  that hold a link to the identifier are written.

  Each schema whose table holds the text is rewritten as a step of its own:
  one that fails is logged and keeps its links as they were, and the
  schemas after it are still rewritten. Inside a caller's transaction (a
  revision restore saves the identifier in one), each step runs in a
  savepoint and a failed one is rolled back to it, its writes and queued
  renders with it.

  A row is written once, by the first schema whose pass finds the link. An
  entry rendered for it is rendered for each of `modules` on the same table
  too, whichever of them came first.

  Forms open on an entry whose rows were rewritten are told, as of a save,
  once the transaction around the rewrite commits, and not when it rolls
  back or the schema's step fails. That needs a transaction begun with
  `Brando.Repo.transaction/1`: in one begun on the application's Ecto repo
  directly, they are told at once, before the commit, and also when it
  rolls back.
  """
  def update_identifier_links_in_rich_text_fields(identifier_id, new_url, modules \\ identifier_link_modules()) do
    if RichText.allowed_uri?(new_url) do
      tables = modules_by_table(modules)

      for {schema, target} <- rich_text_targets(modules),
          do: update_identifier_links_in_schema(schema, target, identifier_id, new_url, tables)
    end
  end

  # The walked modules by their table: `{prefix, source}`
  defp modules_by_table(modules),
    do: modules |> Enum.uniq() |> Enum.group_by(&table_of/1)

  defp table_of(module), do: {module.__schema__(:prefix), module.__schema__(:source)}

  @doc """
  The Blueprint modules whose rich text a moved identifier's links are
  rewritten in: the application's Blueprints and Brando's pages and
  fragments (`Brando.Blueprint.list_blueprints/1`) that have a table. A table shared
  by every site and environment (`Brando.Tenant.SharedTables`, or a schema
  in `public`) is left out unless the module persists identifiers: an
  identifier's id does not tell two sites' identifiers apart.
  """
  def identifier_link_modules do
    for module <- Enum.uniq(Brando.Blueprint.list_blueprints(:include_brando)),
        identifier_link_source?(module),
        do: module
  end

  # A schema whose rows a moved identifier's links are looked for in: one
  # with a table, which is a site's own unless the schema persists
  # identifiers. The walked modules and the rows their subforms draw from
  # another table are both held to it.
  defp identifier_link_source?(module) do
    source = module.__schema__(:source)

    is_binary(source) and
      (Brando.Content.Identifier.Registry.has_persistent_identifier?(module) or not shared_source?(module, source))
  end

  defp shared_source?(module, source),
    do: module.__schema__(:prefix) == "public" or Brando.Tenant.SharedTables.member?(source)

  # One step of rewriting a moved identifier's links, so that a failure in
  # it does not stop the steps after it: the failure is logged with `step`
  # and the reason, and the step's rows keep the address they had. Inside a
  # caller's transaction the step runs in a savepoint and is rolled back to
  # it, its writes and queued renders with it: a failed statement would
  # otherwise abort the caller's transaction. Outside one, each row has
  # committed by itself.
  defp isolate_identifier_link_step(step, fun) do
    if Repo.repo().in_transaction?() do
      Repo.repo().query!("SAVEPOINT brando_identifier_links", [])

      try do
        fun.()
      catch
        kind, reason ->
          Repo.repo().query!("ROLLBACK TO SAVEPOINT brando_identifier_links", [])
          log_identifier_link_failure(step, kind, reason, __STACKTRACE__)
      else
        result ->
          Repo.repo().query!("RELEASE SAVEPOINT brando_identifier_links", [])
          result
      end
    else
      try do
        fun.()
      catch
        kind, reason -> log_identifier_link_failure(step, kind, reason, __STACKTRACE__)
      end
    end
  end

  defp log_identifier_link_failure(step, kind, reason, stacktrace) do
    require Logger

    step = if is_atom(step), do: inspect(step), else: step

    Logger.error(
      "[Brando.Content.Blocks] Rewriting links to a moved identifier in #{step} failed; " <>
        "they keep their old address until the address changes again: " <>
        Exception.format(kind, reason, stacktrace)
    )

    :error
  end

  # One row per transaction, so a rewrite holds one lock at a time. In a
  # caller's transaction the step's savepoint takes a failure back instead: a
  # nested transaction that raised would roll back the caller's as well.
  defp in_holder_transaction(fun) do
    if Repo.repo().in_transaction?() do
      fun.()
    else
      case Repo.transaction(fun) do
        {:ok, result} -> result
        {:error, _reason} -> :ok
      end
    end
  end

  defp update_identifier_links_in_schema(schema, target, identifier_id, new_url, tables) do
    isolate_identifier_link_step(schema, fn ->
      rewrites =
        column_rewrites(schema, target, identifier_id, new_url) ++
          Enum.flat_map(target.embeds, &embed_rewrites(schema, &1, identifier_id, new_url))

      rewrite_identifier_links(rewrites, [], tables)
    end)
  end

  # Rows in the schema's own table: the schema's own rich-text columns, and
  # those of rows drawn as a `has_one` / `has_many` subform of other schemas
  # (the owners rendered with the row)
  defp column_rewrites(_schema, %{fields: []}, _identifier_id, _new_url), do: []

  defp column_rewrites(schema, %{fields: fields, owners: owners}, identifier_id, new_url) do
    linked = Enum.reduce(fields, dynamic(false), &dynamic([row], ^&2 or ilike(field(row, ^&1), "%data-identifier-id%")))
    query = from row in schema, where: ^linked, where: ^held_by_owner(owners), select: map(row, ^[:id | fields])

    for row <- Repo.all(query),
        row_contains_identifier?(row, fields, identifier_id),
        do: fn -> update_locked_row_identifier_link(schema, fields, owners, row.id, identifier_id, new_url) end
  end

  # A row only a parent's subform draws is looked for while it has a parent
  defp held_by_owner(owners) do
    if :self in owners do
      dynamic(true)
    else
      Enum.reduce(owners, dynamic(false), fn {_module, %{related_key: key}}, held ->
        dynamic([row], ^held or not is_nil(field(row, ^key)))
      end)
    end
  end

  # Rows stored in the entry's own column: the entry is the owner locked
  defp embed_rewrites(schema, {name, fields}, identifier_id, new_url) do
    query =
      from entry in schema,
        where: fragment("CAST(? AS TEXT) ILIKE ?", field(entry, ^name), "%data-identifier-id%"),
        select: {entry.id, field(entry, ^name)}

    for {id, rows} <- Repo.all(query),
        Enum.any?(List.wrap(rows), &row_contains_identifier?(&1, fields, identifier_id)),
        do: fn -> update_locked_embed_identifier_link(schema, name, fields, id, identifier_id, new_url) end
  end

  defp row_contains_identifier?(%{} = row, fields, identifier_id),
    do: Enum.any?(fields, &RichText.contains_identifier?(Map.get(row, &1), identifier_id))

  defp row_contains_identifier?(_row, _fields, _identifier_id), do: false

  # In the bulk lane: a link that moved can reach any number of entries.
  # `rewritten` is kept newest first and reversed once.
  defp rewrite_identifier_links([], rewritten, tables), do: rewritten_entries(Enum.reverse(rewritten), tables)

  defp rewrite_identifier_links([rewrite | rewrites], rewritten, tables) do
    result =
      try do
        in_holder_transaction(rewrite)
      catch
        # Outside a caller's transaction each row has committed by itself:
        # the entries rewritten before this one still get their renders. In
        # one, the step's savepoint takes them back.
        kind, reason ->
          unless Repo.repo().in_transaction?(), do: rewritten_entries(Enum.reverse(rewritten), tables)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    rewritten =
      case result do
        {:updated, entries} -> Enum.reverse(entries, rewritten)
        _ -> rewritten
      end

    rewrite_identifier_links(rewrites, rewritten, tables)
  end

  # The entries whose rows were rewritten, those in the trash too: a restore
  # does not render an ordinary entry, so it is rendered now to come back
  # with the new address. Each is told to its open forms and rendered for
  # every walked module on its table as well: a later module's pass finds
  # the row already rewritten and queues nothing. The cache is kept by
  # table, so the eviction of the rewrite covers them.
  defp rewritten_entries(entries, tables) do
    entries =
      entries
      |> Enum.flat_map(fn {schema, id} = entry ->
        [entry | for(module <- Map.get(tables, table_of(schema), []), do: {module, id})]
      end)
      |> Enum.uniq()

    # In a caller's transaction, told once the renders are queued: a failure
    # rolls the step back to its savepoint, and its entries are as they were.
    # Outside one, each row has committed by itself, renders or not.
    if Repo.repo().in_transaction?() do
      enqueue_rewritten_for_render(entries)
      Enum.each(entries, &announce_rewritten/1)
    else
      Enum.each(entries, &announce_rewritten/1)
      enqueue_rewritten_for_render(entries)
    end
  end

  # Only entries the render can load: a row of a schema without a context
  # function of its own is evicted, not rendered.
  defp enqueue_rewritten_for_render(entries) do
    case Enum.filter(entries, fn {schema, _id} -> Brando.Blueprint.EntryQuery.loadable?(schema) end) do
      [] -> :ok
      entries -> entries |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> enqueue_entry_map_for_render()
    end
  end

  # Open forms on the entry take the rewritten rows as they take another
  # editor's save (`take_saved_entry` in the admin Form), keeping what the
  # editor changed. Saved by no editor, so no tab is left out. Once the
  # rewrite has committed: the forms read the entry again. The topic is the
  # rewrite's environment, which may not be the one current at the commit.
  defp announce_rewritten({schema, id}) do
    topic = Brando.Tenant.Topic.entry("field_sync", schema, id)

    Repo.after_commit(fn ->
      Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:entry_saved, %{tab: nil, user_id: nil}})
    end)
  end

  # Lock only the matching row while rewriting. A concurrent author must
  # never lose new wording to a stale read/replace operation. A row another
  # editor detached from its parent (`on_replace: :nilify`) since the scan is
  # rewritten, but has no parent to render.
  defp update_locked_row_identifier_link(schema, fields, owners, id, identifier_id, new_url) do
    row = Repo.one(from row in schema, where: row.id == ^id, lock: "FOR UPDATE")
    changes = if row, do: relinked_fields(row, fields, identifier_id, new_url), else: %{}

    if changes == %{} do
      :ok
    else
      updated = row |> Changeset.change(changes) |> Repo.update!()
      Brando.Cache.Query.evict({:ok, updated})
      {:updated, Enum.flat_map(owners, &owner_to_render(&1, updated))}
    end
  end

  defp owner_to_render(:self, %{__struct__: schema, id: id}), do: [{schema, id}]

  defp owner_to_render({module, %{related_key: related_key, owner_key: owner_key}}, row) do
    with owner_value when not is_nil(owner_value) <- Map.fetch!(row, related_key),
         %{} = entry <- Repo.one(from entry in module, where: field(entry, ^owner_key) == ^owner_value) do
      Brando.Cache.Query.evict({:ok, entry})
      [{module, entry.id}]
    else
      _ -> []
    end
  end

  # The column is read by itself, so a relation the entry's query leaves out
  # (`load_in_query: false`) is read too, and written with `update_all`: a
  # changeset would go through the relation's `on_replace`, which refuses a
  # changed row for `:raise`, and for `:update` on a row without a primary
  # key. The rows keep their ids and every other key.
  defp update_locked_embed_identifier_link(schema, name, fields, id, identifier_id, new_url) do
    rows =
      Repo.one(from entry in schema, where: entry.id == ^id, lock: "FOR UPDATE", select: {entry.id, field(entry, ^name)})

    with {_id, rows} <- rows,
         {:updated, rows} <- relink_embedded_rows(rows, fields, identifier_id, new_url) do
      set = [{name, rows} | autoupdated_fields(schema)]

      {1, [updated]} =
        Repo.update_all(from(entry in schema, where: entry.id == ^id, select: entry), set: set)

      Brando.Cache.Query.evict({:ok, updated})
      {:updated, [{schema, id}]}
    else
      _ -> :ok
    end
  end

  # What `Repo.update` would set: `updated_at` and any other `autoupdate`
  defp autoupdated_fields(module) do
    for {fields, {mod, fun, args}} <- module.__schema__(:autoupdate),
        value = apply(mod, fun, args),
        field <- fields,
        do: {field, value}
  end

  defp relink_embedded_rows(rows, fields, identifier_id, new_url) when is_list(rows) do
    relinked = Enum.map(rows, &relink_row_struct(&1, fields, identifier_id, new_url))

    if relinked != rows,
      do: {:updated, relinked},
      else: :unchanged
  end

  defp relink_embedded_rows(%{} = row, fields, identifier_id, new_url) do
    relinked = relink_row_struct(row, fields, identifier_id, new_url)
    if relinked != row, do: {:updated, relinked}, else: :unchanged
  end

  defp relink_embedded_rows(_rows, _fields, _identifier_id, _new_url), do: :unchanged

  defp relink_row_struct(row, fields, identifier_id, new_url),
    do: Map.merge(row, relinked_fields(row, fields, identifier_id, new_url))

  defp relinked_fields(row, fields, identifier_id, new_url) do
    for field <- fields,
        {:updated, html} <- [RichText.update_identifier_url(Map.get(row, field), identifier_id, new_url)],
        into: %{},
        do: {field, html}
  end

  @doc """
  The rich text of `modules` that a moved identifier's URL is rewritten in,
  by the schema whose table holds it: `{schema, %{fields: fields, owners:
  owners, embeds: embeds}}`, in the order the schemas are first met.

    * `fields` are rich-text columns of the schema's own rows: its own
      `:rich_text` inputs (`rich_text_fields_for/1`), and those of rows
      another module draws as a `has_one` / `has_many` subform, unless
      their table is shared as `identifier_link_modules/0` leaves out a
      module's. `owners`
      are the entries rendered when a row changes: `:self`, the row itself,
      and `{module, association}`, the row's parent.
    * `embeds` are `{column, fields}`: the rich-text inputs of the rows a
      subform stores in the schema's own column (`embeds_one`,
      `embeds_many`).

  A column several modules or forms reach is rewritten once, and renders
  every owner whichever was met first.
  """
  def rich_text_targets(modules) do
    Enum.reduce(modules, [], fn module, targets ->
      targets = put_target(targets, module, %{fields: rich_text_fields_for(module), owners: [:self], embeds: []})

      module
      |> subform_rich_text_fields_for()
      |> Enum.filter(&identifier_link_subform?/1)
      |> Enum.reduce(targets, fn
        {:embed, name, fields}, targets ->
          put_target(targets, module, %{fields: [], owners: [], embeds: [{name, fields}]})

        {:assoc, %{related: related} = assoc, fields}, targets ->
          put_target(targets, related, %{fields: fields, owners: [{module, assoc}], embeds: []})
      end)
    end)
    |> Enum.reject(fn {_schema, target} -> target.fields == [] and target.embeds == [] end)
  end

  # Rows in the entry's own column, or in a table held to the walked modules' rule
  defp identifier_link_subform?({:embed, _name, _fields}), do: true
  defp identifier_link_subform?({:assoc, %{related: related}, _fields}), do: identifier_link_source?(related)

  defp put_target(targets, _schema, %{fields: [], embeds: []}), do: targets

  defp put_target(targets, schema, target) do
    case List.keyfind(targets, schema, 0) do
      nil ->
        targets ++ [{schema, target}]

      {^schema, known} ->
        merged = %{
          fields: Enum.uniq(known.fields ++ target.fields),
          owners: Enum.uniq(known.owners ++ target.owners),
          embeds: merge_relations(known.embeds ++ target.embeds)
        }

        List.keyreplace(targets, schema, 0, {schema, merged})
    end
  end

  # A relation several forms draw: the rich-text inputs of each
  defp merge_relations(relations) do
    Enum.reduce(relations, [], fn {relation, fields}, merged ->
      case List.keyfind(merged, relation, 0) do
        nil -> merged ++ [{relation, fields}]
        {_relation, known} -> List.keyreplace(merged, relation, 0, {relation, Enum.uniq(known ++ fields)})
      end
    end)
  end

  @doc """
  The rich-text inputs of the subform rows in each of a blueprint `module`'s
  forms that a moved identifier's URL is rewritten in: `{:embed, name,
  fields}` for rows stored in the entry's column (`embeds_one`,
  `embeds_many`), and `{:assoc, association, fields}` for rows with a table
  of their own (`has_one`, `has_many`). A relation several forms draw is
  listed once, with the rich-text inputs of each.
  """
  def subform_rich_text_fields_for(module) do
    subforms =
      for %{tabs: tabs} when is_list(tabs) <- blueprint_forms(module),
          %{fields: fieldsets} <- tabs,
          %{fields: inputs} <- fieldsets,
          %Brando.Blueprint.Forms.Subform{name: name, sub_fields: sub_fields} <- inputs,
          subform = subform_rich_text_fields(module, name, sub_fields),
          subform != nil,
          do: subform

    kinds = Map.new(subforms, fn {kind, relation, _fields} -> {relation, kind} end)

    subforms
    |> Enum.map(fn {_kind, relation, fields} -> {relation, fields} end)
    |> merge_relations()
    |> Enum.map(fn {relation, fields} -> {Map.fetch!(kinds, relation), relation, fields} end)
  end

  defp subform_rich_text_fields(module, name, sub_fields) do
    rich_names = for %Brando.Blueprint.Forms.Input{type: :rich_text, name: field} <- sub_fields, do: field

    case {module.__schema__(:embed, name), module.__schema__(:association, name)} do
      {%Ecto.Embedded{related: related}, _} ->
        subform_entry(:embed, name, related, rich_names)

      {nil, %Ecto.Association.Has{related: related} = assoc} ->
        subform_entry(:assoc, assoc, related, rich_names)

      _ ->
        nil
    end
  end

  defp subform_entry(kind, relation, related, rich_names) do
    case Enum.filter(rich_names, &(&1 in related.__schema__(:fields))) do
      [] -> nil
      fields -> {kind, relation, fields}
    end
  end

  @doc """
  The rich-text columns of a blueprint `module` that a moved identifier's
  URL is rewritten in: the `:rich_text` inputs at the top of each of its
  forms that are columns of the module. A column that one form draws as
  rich text and another as plain text is among them.
  """
  def rich_text_fields_for(module) do
    for %{tabs: tabs} when is_list(tabs) <- blueprint_forms(module),
        %{fields: fieldsets} <- tabs,
        %{fields: inputs} <- fieldsets,
        %Brando.Blueprint.Forms.Input{type: :rich_text, name: name} <- inputs,
        name in module.__schema__(:fields),
        uniq: true,
        do: name
  end

  defp blueprint_forms(module) do
    if Brando.Blueprint.blueprint?(module), do: module.__forms__(), else: []
  end

  @doc """
  Look through all `villains` for `search_term` and rerender all matching
  """
  def render_entries_matching_regex(search_terms) do
    search_terms
    |> list_block_ids_matching_regex()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Renders again, in each of `environments` of the site `site_key`, the entries
  whose blocks emit JSON-LD (`json_ld` in a module's code or a block's refs):
  what they store names the site's public base URL, its live environment's
  domain (`Brando.Utils.public_hostname/0`). The renders are queued. An
  environment without its tables yet (being provisioned) has nothing stored.

  Each environment is searched under its own prefix, unscoped (an admin's
  scope names the environment it was taken in), and in a transaction of its
  own: one that fails is logged and queues nothing, and the others still
  queue theirs.
  """
  @spec rerender_public_urls(String.t(), [Brando.Environments.Environment.t()]) :: :ok
  def rerender_public_urls(site_key, environments) do
    search_terms = Villain.RenderInvalidation.patterns([:json_ld])

    Brando.Authorization.Boundary.with_scope(nil, fn ->
      Enum.each(environments, &rerender_public_urls_in(Brando.Tenant.prefix(site_key, &1.key), search_terms))
    end)
  end

  defp rerender_public_urls_in(prefix, search_terms) do
    Brando.Tenant.with_prefix(prefix, fn ->
      Repo.transaction(fn -> rerender_stored(prefix, search_terms) end)
    end)
  rescue
    error ->
      require Logger

      Logger.error(
        "Could not queue the renders of #{prefix}'s stored JSON-LD for its site's public base URL: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )
  end

  defp rerender_stored(prefix, search_terms) do
    if Brando.Migration.Introspect.table_exists?("content_blocks", prefix: prefix, repo: Repo.repo()) do
      render_entries_matching_regex(search_terms)
      rerender_matching_modules(search_terms)
    end
  end

  @doc """
  Look through all modules for `search_terms` and rerender all villains that
  use this module
  """
  @spec rerender_matching_modules({atom, binary} | [{atom, binary}]) :: any
  def rerender_matching_modules(search_terms) do
    for {origin, id} <- list_modules_matching_regex(search_terms), do: render_entries_with_module_id(id, origin)
  end

  @doc """
  The modules the current environment renders with whose `code` matches one
  of `search_terms`, as `{origin, id}`, as block rendering resolves them
  (`Brando.Content.SharedLibrary`): its own modules, and the shared ones,
  where its override of a shared module is matched in the shared module's
  place. Soft-deleted modules are left out.
  """
  @spec list_modules_matching_regex({atom, binary} | [{atom, binary}]) :: [{:local | :shared, integer}]
  def list_modules_matching_regex(search_terms) do
    matches =
      search_terms
      |> List.wrap()
      |> Enum.reduce(dynamic(false), fn {_name, term}, matches ->
        dynamic([m], ^matches or fragment("CAST(? AS TEXT) ~ ?", m.code, ^term))
      end)

    active = from(m in Content.Module, where: is_nil(m.deleted_at))
    matching = Repo.all(from(m in active, where: ^matches, select: {m.id, m.source_module_id}))

    overridden =
      MapSet.new(Repo.all(from(m in active, where: not is_nil(m.source_module_id), select: m.source_module_id)))

    own = for {id, nil} <- matching, do: {:local, id}
    overrides = for {_id, source_id} <- matching, source_id, do: {:shared, source_id}

    shared =
      for id <- list_shared_modules_matching(matches), not MapSet.member?(overridden, id), do: {:shared, id}

    own ++ overrides ++ shared
  end

  # Shared modules live in `public`, used by an environment of a site
  defp list_shared_modules_matching(matches) do
    if is_binary(Brando.Tenant.current_prefix()) and Brando.Tenant.current_site_key() do
      Repo.all(from(m in Content.Module, where: is_nil(m.deleted_at), where: ^matches, select: m.id), prefix: "public")
    else
      []
    end
  end

  @doc """
  Enqueue an async cascade job that merges datasource + identifier cascade
  discovery and enqueues EntryRenderer jobs in the background.

  The cascade leaves out `entry` itself, which its save rendered, unless
  `render_entry: true` says the save changed what its own blocks show and did
  not render them: a status change outside the form, for blocks that link to
  the entry itself (`get_entry`).
  """
  def enqueue_entry_cascade(module, entry, identifier_id, opts \\ []) do
    render_entry? = Keyword.get(opts, :render_entry, false)

    changeset =
      %{schema: to_string(module), entry_id: entry.id, identifier_id: identifier_id}
      |> then(&if(render_entry?, do: Map.put(&1, :render_entry, true), else: &1))
      |> Brando.Tenant.Job.attach()
      |> Brando.Worker.EntryCascade.new()
      |> Brando.Content.RenderRun.tag()

    # One queued and not started yet runs for this write too
    changeset
    |> Oban.insert()
    |> Brando.Content.RenderQueue.coalesce(changeset, fn args, _ ->
      args
      |> Map.update("identifier_id", identifier_id, &(&1 || identifier_id))
      |> then(&if(render_entry?, do: Map.put(&1, "render_entry", true), else: &1))
    end)
  end

  @doc """
  Enqueues every entry in a schema-to-entry-ids map for rendering, in the
  bulk lane (`Brando.Content.RenderQueue.enqueue_map/2`).
  """
  defdelegate enqueue_entry_map_for_render(entry_map), to: Brando.Content.RenderQueue, as: :enqueue_map

  @doc """
  Enqueues all `ids` for `schema` for rendering, in the bulk lane
  (`Brando.Content.RenderQueue.enqueue_many/3`).
  """
  defdelegate enqueue_entries_for_render(schema, ids), to: Brando.Content.RenderQueue, as: :enqueue_many

  @doc """
  Enqueues one entry-rendering job (`Brando.Content.RenderQueue.enqueue/2`).
  """
  defdelegate enqueue_entry_for_render(args, opts \\ []), to: Brando.Content.RenderQueue, as: :enqueue

  # --- Entry Rendering Orchestration ---

  @doc """
  Render all entries for `schema`
  """
  def render_all_entries(schema) do
    entry_ids =
      Repo.all(
        from(s in schema,
          select: s.id
        )
      )

    enqueue_entries_for_render(schema, entry_ids)
  end

  @doc """
  Rerender multiple IDS
  """
  @spec render_entries(schema :: module, ids :: [integer | binary]) :: [any()]
  def render_entries(_, []), do: []

  def render_entries(schema, ids),
    do: for(id <- ids, do: render_entry(schema, id))

  @doc """
  Rerender HTML from an ID.

  We treat page fragments special, since they need to propagate to other
  referencing pages and fragments.

  The render stores only if the entry's row is as it was when the render
  loaded it, and renders again from the entry as it is now if not: an
  editor's save, which renders inline, may have stored newer blocks while it
  rendered (`store_render/5`). After #{@render_attempts} renders that each
  lost to a write it returns `{:error, :entry_changed}`.

  When a block template fails (`render_fields/3`), nothing is stored: the
  entry keeps the HTML it had, a fragment's embedding entries are not
  rendered again, and it returns `{:error, {:render_failed, failures}}`, a
  `Brando.Villain.RenderFailure` for each failing block, after logging them
  once.
  """
  @spec render_entry(schema :: module, entry_id :: integer | binary) ::
          {:ok, map}
          | {:error, changeset | :entry_changed | {:render_failed, [Brando.Villain.RenderFailure.t()]} | term}
  @decorate span("brando.blocks.render_entry", schema: :schema, entry_id: :id)
  def render_entry(schema, id) do
    case render_and_store(schema, id) do
      {:ok, %{__struct__: fragment_module} = fragment} when fragment_module == @fragment_module ->
        Brando.Cache.Query.evict({:ok, fragment})
        render_entries_with_fragment_id(fragment.id)
        {:ok, fragment}

      {:ok, result} ->
        Brando.Cache.Query.evict({:ok, result})
        {:ok, result}

      {:error, %Changeset{}} = err ->
        err

      {:error, {:render_failed, failures}} = err ->
        log_render_failure(schema, id, failures)
        err

      {:error, _} = err ->
        log_render_error(schema, id, err)
    end
  end

  @doc false
  # Loads the entry, renders it and stores the HTML under the check
  # `render_entry/2` describes, and nothing after: no cache eviction, no
  # fragment cascade. For `mix brando.entries.resave`, which stores each
  # entry with `prepare: fun` applied to the rendered changeset and
  # `force: true` passed to the update. A render with a failing block template
  # stores nothing and returns `{:error, {:render_failed, failures}}`, unlogged.
  @spec render_and_store(module, term, keyword) ::
          {:ok, map}
          | {:error, changeset | :entry_changed | {:render_failed, [Brando.Villain.RenderFailure.t()]} | term}
  def render_and_store(schema, id, opts \\ []), do: render_and_store(schema, id, opts, @render_attempts)

  defp render_and_store(schema, id, opts, attempts) do
    # Read before the entry: a write in between makes the render again,
    # never one that goes unseen
    version = Repo.one(row_version(schema, id))

    prepare = Keyword.get(opts, :prepare, & &1)

    with {:ok, entry} <- Brando.Blueprint.EntryQuery.get(schema, id),
         {:ok, rendered} <- render_fields(schema, entry) do
      changeset =
        entry
        |> Changeset.change()
        |> put_rendered(rendered, :if_changed)
        |> prepare.()

      case store_render(schema, id, version, changeset, Keyword.take(opts, [:force])) do
        :changed when attempts > 1 -> render_and_store(schema, id, opts, attempts - 1)
        :changed -> {:error, :entry_changed}
        result -> result
      end
    end
  end

  # Under the row's lock, briefly: the render is done. A save that writes
  # the row while this holds it waits, and stores after it. One that wrote
  # it since the render read it changed its version (`xmin`, which every
  # write of the row moves), and every save that renders inline writes the
  # row (it forces its `rendered_*_at`), so this renders again from what
  # that save stored. A render that changes nothing stores nothing (unless
  # forced), but checks all the same: the entry it returns is what the
  # caller acts on.
  #
  # NO KEY UPDATE, as the update takes: FOR UPDATE would also wait for
  # inserts of rows that point at the entry.
  defp store_render(schema, id, version, %Changeset{changes: changes} = changeset, [])
       when changes == %{} do
    if version != nil and Repo.one(row_version(schema, id)) == version, do: {:ok, changeset.data}, else: :changed
  end

  defp store_render(schema, id, version, changeset, update_opts) do
    # Nested, Ecto takes no savepoint: a rollback would abort the caller's
    # transaction too, so the failed update is returned instead
    nested? = Repo.repo().in_transaction?()

    Repo.transaction(fn ->
      if version != nil and Repo.one(lock(row_version(schema, id), "FOR NO KEY UPDATE")) == version,
        do: update_render(changeset, update_opts, nested?),
        else: :changed
    end)
    |> case do
      {:ok, :changed} -> :changed
      {:ok, {:error, _} = err} -> err
      result -> result
    end
  end

  defp update_render(changeset, update_opts, nested?) do
    case Repo.update(changeset, update_opts) do
      {:ok, stored} -> stored
      {:error, _} = err when nested? -> err
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # The version of the entry's row: the transaction that wrote it last
  defp row_version(schema, id), do: from(e in schema, where: e.id == ^id, select: fragment("xmin::text"))

  defp log_render_error(schema, id, err) do
    require Logger

    Logger.error("""
    ==> Failed to render_entry/2

    Schema..: #{inspect(schema, pretty: true)}
    Id......: #{inspect(id, pretty: true)}

    ERROR:
    #{inspect(err, pretty: true)}

    """)

    err
  end

  @doc """
  What `store_fenced/3` checks a save against: the version of the entry's
  row before an inline render. Take it before rendering. Nil for a new entry.
  """
  @spec render_fence(changeset) :: {module, term, String.t() | nil} | nil
  def render_fence(%Changeset{data: %{__struct__: schema, id: id}}) when not is_nil(id),
    do: {schema, id, Repo.one(row_version(schema, id))}

  def render_fence(_changeset), do: nil

  @doc """
  Saves `changeset`, rendered inline after `fence` was taken
  (`render_fence/1`), with `save`, a function that stores it and returns
  `{:ok, entry}` or an error.

  A background render that stored the entry while this one rendered may have
  read newer modules, globals or fragments than this one did, and this save
  stores over it: once the save succeeds, the entry is queued for a render.
  This node rendered from inputs it had not caught up with, though its own
  tokens may say it has, so whichever node runs that render refreshes every
  render input first (`Brando.Content.RenderQueue.enqueue/2`).
  The save checks under the row's lock, which it holds until it commits, so
  a render can't store between the check and the save. A background render
  still running then renders again from what the save stored
  (`render_entry/2`).
  """
  @spec store_fenced({module, term, String.t() | nil} | nil, changeset, (changeset -> result)) :: result
        when result: term
  def store_fenced(nil, changeset, save), do: save.(changeset)

  def store_fenced({schema, id, version}, changeset, save) do
    written = {__MODULE__, :written_since_render, make_ref()}

    changeset =
      Changeset.prepare_changes(changeset, fn changeset ->
        # The lock the save's update takes, as in `store_render/5`
        if Repo.one(lock(row_version(schema, id), "FOR NO KEY UPDATE")) != version,
          do: Process.put(written, true)

        changeset
      end)

    {result, written?} =
      try do
        {save.(changeset), Process.get(written, false)}
      after
        Process.delete(written)
      end

    if written? and match?({:ok, _}, result),
      do: Repo.after_commit(fn -> enqueue_entry_for_render(%{schema: to_string(schema), entry_id: id}, refresh: :all) end)

    result
  end

  # --- Module Sync ---

  @doc """
  Ids of blocks that have not been migrated to a module's current revision.

  A block is stale when its `module_version` is behind the module's `version`, or
  is missing entirely (a block created before migration tracking landed and never
  re-synced since). Stale means the block still holds data — refs or vars the
  module no longer defines, or whose type it changed — that no definition backs
  any more. It renders through the module's current code regardless; the version
  gap is what makes the mismatch findable.

  The Legacy Content Wrapper's `content` ref holds a ref of any type
  (`Brando.Content.Module.any_ref_type?/2`). A save of the wrapper before
  that was so left its blocks behind with nothing else to resolve: those
  are not stale.
  """
  @spec list_stale_block_ids(ContentModule.t() | integer(), atom()) :: [integer()]
  def list_stale_block_ids(module_or_id, origin \\ :local)

  def list_stale_block_ids(%{id: module_id, version: version} = module, origin),
    do: module_id |> query_stale_block_ids(version || 1, origin) |> reject_current_wrapper_blocks(module)

  def list_stale_block_ids(module_id, origin) when is_integer(module_id) do
    case Repo.get(ContentModule, module_id) do
      nil -> []
      module -> list_stale_block_ids(module, origin)
    end
  end

  @doc "How many blocks are behind `module`'s current revision. See `list_stale_block_ids/2`."
  @spec count_stale_blocks(ContentModule.t() | integer(), atom()) :: non_neg_integer()
  def count_stale_blocks(module_or_id, origin \\ :local),
    do: module_or_id |> list_stale_block_ids(origin) |> length()

  @doc """
  Stale blocks per module, for every module that has any: `[{module, count}]`,
  most first. The same test as `list_stale_block_ids/2`: one query, and for
  the Legacy Content Wrapper a look at its blocks behind its version.
  """
  @spec count_stale_blocks_by_module(atom()) :: [{ContentModule.t(), pos_integer()}]
  def count_stale_blocks_by_module(origin \\ :local) do
    from(b in Block,
      join: m in ContentModule,
      on: m.id == b.module_id,
      where: is_nil(b.module_version) or b.module_version < coalesce(m.version, 1),
      group_by: m.id,
      order_by: [desc: count(b.id), asc: m.id],
      select: {m, count(b.id)}
    )
    |> maybe_filter_library_origin(:module_origin, origin)
    |> Repo.all()
    |> Enum.map(&recount_wrapper(&1, origin))
    |> Enum.reject(&match?({_module, 0}, &1))
    |> Enum.sort_by(fn {module, count} -> {-count, module.id} end)
  end

  defp recount_wrapper({module, count}, origin) do
    if ContentModule.legacy_wrapper?(module),
      do: {module, length(list_stale_block_ids(module, origin))},
      else: {module, count}
  end

  defp query_stale_block_ids(module_id, version, origin) do
    from(b in Block,
      where: b.module_id == ^module_id,
      where: is_nil(b.module_version) or b.module_version < ^version,
      select: b.id
    )
    |> maybe_filter_library_origin(:module_origin, origin)
    |> Repo.all()
  end

  # Behind the wrapper's version, a block whose refs and vars the wrapper all
  # backs (any type in `content`) is current: only a save of the wrapper
  # from before `content` held any type left it there. The same test as
  # `sync_module/2` stamps with. Only the wrapper's blocks are loaded.
  defp reject_current_wrapper_blocks([], _module), do: []

  defp reject_current_wrapper_blocks(ids, module) do
    if ContentModule.legacy_wrapper?(module) do
      module = Repo.preload(module, [:refs, :vars])
      refs_by_name = Map.new(module.refs, &{&1.name, &1})
      var_keys = Enum.map(module.vars, & &1.key)

      current =
        from(b in Block, where: b.id in ^ids, preload: [:refs, :vars])
        |> Repo.all()
        |> Enum.filter(fn block ->
          refs = Enum.map(block.refs, &Changeset.change/1)
          vars = Enum.map(block.vars, &Changeset.change/1)
          fully_migrated?(module, refs, vars, refs_by_name, var_keys)
        end)
        |> MapSet.new(& &1.id)

      Enum.reject(ids, &MapSet.member?(current, &1))
    else
      ids
    end
  end

  @doc """
  Gets all blocks with `module_id` and reapply refs and vars, then saves them.
  Returns a list of all updated block ids.
  """
  @decorate span("brando.blocks.refresh_module", module_id: :module_id)
  def refresh_module_in_blocks(module_id) do
    {:ok, module} =
      Content.get_module(%{
        matches: %{id: module_id},
        preload: [:vars, refs: Ref.preloads()]
      })

    {:ok, blocks} =
      Content.list_blocks(%{
        filter: %{module_id: module_id},
        preload: [:vars, refs: Ref.preloads()]
      })

    Tracing.set_attributes(%{"brando.block_count": length(blocks)})

    blocks
    |> Enum.reduce([], fn block, acc ->
      case block |> sync_module(module) |> Repo.update() do
        {:ok, _} -> [block.id | acc]
        {:error, changeset} -> log_failed_sync(block, module, changeset, acc)
      end
    end)
  end

  @doc """
  Syncs a block's vars and refs with a module.

  Called for every block using a module each time that module is saved, so this
  is the site-wide migration path — see `Brando.Content.ModuleDiff`.

  Refs and vars the module no longer defines are **retained**, not deleted. Their
  data is the editor's, not the module's, and a removal is indistinguishable from
  a rename here; deleting it destroyed content across every entry on the site
  with no way back. The module's template no longer references them, so they lie
  dormant until an explicit upgrade resolves them.

  A block left holding such orphans — or a ref whose type the module changed
  underneath it — is not stamped with the module's current version. It stays
  discoverable through `list_stale_block_ids/2` instead of quietly claiming to be
  up to date.
  """
  def sync_module(block, module) do
    module_refs = module.refs
    module_refs_by_name = Map.new(module_refs, &{&1.name, &1})
    module_ref_names = Enum.map(module_refs, & &1.name)
    changeset = Changeset.change(block)

    current_refs = Changeset.get_assoc(changeset, :refs)

    current_ref_names = Enum.map(current_refs, &Changeset.get_field(&1, :name))
    missing_ref_names = module_ref_names -- current_ref_names

    missing_refs =
      module_refs
      |> Enum.filter(&(&1.name in missing_ref_names))
      |> force_new_uids_for_refs()
      |> remove_pk_from_refs()
      |> Enum.map(&Changeset.change/1)
      |> Enum.map(&%{&1 | action: :insert})

    new_refs = current_refs ++ missing_refs

    module_vars = module.vars || []
    module_var_keys = Enum.map(module_vars, & &1.key)

    current_vars = Changeset.get_assoc(changeset, :vars)
    current_var_keys = Enum.map(current_vars, &Changeset.get_field(&1, :key))

    missing_var_keys = module_var_keys -- current_var_keys

    missing_vars =
      module_vars
      |> Enum.filter(&(&1.key in missing_var_keys))
      |> remove_pk_from_vars()
      |> Enum.map(&Changeset.change/1)
      |> Enum.map(&%{&1 | action: :insert})

    new_vars = current_vars ++ missing_vars

    reapplied_refs = reapply_refs(module, module_refs, new_refs)
    reapplied_vars = reapply_vars(module, module_vars, new_vars)

    changeset
    |> Changeset.put_assoc(:vars, reapplied_vars)
    |> Changeset.put_assoc(:refs, reapplied_refs)
    |> stamp_module_version(module, reapplied_refs, new_vars, module_refs_by_name, module_var_keys)
  end

  # `module_version` means "the newest module revision whose instance-data
  # migration was successfully applied to this block". Only stamp it when every
  # ref and var the block holds still has a definition of the same type behind
  # it; anything else is data awaiting review, and claiming it current would make
  # the stale count useless.
  defp stamp_module_version(changeset, module, refs, vars, module_refs_by_name, module_var_keys) do
    if fully_migrated?(module, refs, vars, module_refs_by_name, module_var_keys) do
      Changeset.put_change(changeset, :module_version, module.version || 1)
    else
      changeset
    end
  end

  defp fully_migrated?(module, refs, vars, module_refs_by_name, module_var_keys) do
    Enum.all?(refs, &backed_ref?(&1, module, module_refs_by_name)) and
      Enum.all?(vars, &(Changeset.get_field(&1, :key) in module_var_keys))
  end

  # The module defines this ref and can hold its type. The Legacy Content
  # Wrapper's `content` holds any type (`ContentModule.any_ref_type?/2`); unlike
  # `migratable_ref?/2`, which decides whether the module's definition is
  # applied over the ref, it is not applied there.
  defp backed_ref?(ref_changeset, module, module_refs_by_name) do
    name = Changeset.get_field(ref_changeset, :name)

    migratable_ref?(ref_changeset, module_refs_by_name) or
      (Map.has_key?(module_refs_by_name, name) and ContentModule.any_ref_type?(module, name))
  end

  @doc """
  True when the module still defines this ref, with the same block type.

  A ref whose name is gone, or whose block type the module swapped out from under
  it, cannot be migrated: the stored data does not fit the new definition.
  """
  def migratable_ref?(ref_changeset, module_refs_by_name) do
    case Map.get(module_refs_by_name, Changeset.get_field(ref_changeset, :name)) do
      nil ->
        false

      ref_src ->
        VillainBlocks.ref_types_compatible?(ref_data_type(ref_src), ref_data_type(ref_changeset))
    end
  end

  defp ref_data_type(%Changeset{} = ref_changeset) do
    ref_changeset
    |> Changeset.get_field(:data)
    |> block_data_type()
  end

  defp ref_data_type(%Ref{data: data}), do: block_data_type(data)
  defp ref_data_type(_), do: nil

  # A ref's `data` is a polymorphic embed, and reaches us either as the block
  # struct itself or as a changeset on one, depending on whether anything has
  # already touched it this pass.
  defp block_data_type(%Changeset{data: %{__struct__: struct}}), do: struct
  defp block_data_type(%{__struct__: struct}), do: struct
  defp block_data_type(_), do: nil

  # Returns the ids of the blocks it synced. The entries holding them are
  # re-rendered from scratch by `render_entries_with_module_id/2`.
  def sync_blocks(block_ids, module_id, origin \\ :local)
  def sync_blocks([], _module_id, _origin), do: []

  @decorate span("brando.blocks.sync", module_id: :module_id)
  def sync_blocks(block_ids, module_id, origin) do
    Tracing.set_attributes(%{
      "brando.library_origin": to_string(normalize_library_origin(origin)),
      "brando.block_count": length(block_ids)
    })

    module =
      case normalize_library_origin(origin) do
        :local ->
          {:ok, module} =
            Content.get_module(%{
              matches: %{id: module_id},
              preload: [:vars, refs: Ref.preloads()]
            })

          module

        :shared ->
          Brando.Content.SharedLibrary.get_for_current_tenant(:module, module_id, :shared)
      end

    {:ok, blocks} =
      Content.list_blocks(%{
        filter: %{ids: block_ids},
        preload: [:vars, refs: Ref.preloads()]
      })

    blocks
    |> Enum.reduce([], fn block, acc ->
      case block |> sync_module(module) |> Repo.update() do
        {:ok, _} -> [block.id | acc]
        {:error, changeset} -> log_failed_sync(block, module, changeset, acc)
      end
    end)
  end

  # A module save migrates every block that uses it, one write at a time and
  # outside a transaction. A block that fails keeps its old data and its old
  # `module_version`, so it stays behind the module and shows up in
  # `list_stale_block_ids/2` — a visible queue rather than silent mixed state.
  defp log_failed_sync(block, module, changeset, acc) do
    require Logger

    Logger.error("""
    Failed to sync block ##{block.id} with module ##{module.id}.
    The block keeps its previous data and stays behind module version #{module.version || 1}.

    #{inspect(changeset.errors, pretty: true)}
    """)

    acc
  end

  defp maybe_filter_library_origin(query, _field, nil), do: query

  defp maybe_filter_library_origin(query, field, origin) do
    normalized_origin = normalize_library_origin(origin)
    from entry in query, where: field(entry, ^field) == ^normalized_origin
  end

  defp normalize_library_origin(origin) when origin in [:shared, "shared"], do: :shared
  defp normalize_library_origin(_origin), do: :local

  @doc """
  Reapplies the module's template-controlled ref settings onto a block's refs.

  Refs the module no longer defines, and refs whose block type it swapped out,
  are passed through untouched: a module save is a migration over content the
  editor owns, and neither case is a reason to overwrite it. `sync_module/2`
  leaves such a block behind its module's version so it stays visible as
  needing review.
  """
  def reapply_refs(_module, module_refs, refs) do
    refs_by_name = Map.new(module_refs, &{&1.name, &1})

    Enum.map(refs, fn
      %Changeset{data: %{name: ref_name}} = ref ->
        if migratable_ref?(ref, refs_by_name) do
          ref_src = Map.fetch!(refs_by_name, ref_name)
          block_module = block_data_type(Changeset.get_field(ref, :data))
          block_module.apply_ref(ref_src.data.__struct__, ref_src, apply_ref_principals(ref_src, ref))
        else
          ref
        end
    end)
  end

  defp apply_ref_principals(ref_src, ref_target) do
    ref_target
    |> Changeset.force_change(:name, ref_src.name)
    |> Changeset.force_change(:description, ref_src.description)
  end

  @protected_and_ignored_var_attrs [
    :value,
    :value_boolean,
    :image_id,
    :palette_id,
    :file_id,
    :video_id,
    :gallery_id,
    :form_id,
    :identifier_id,
    :page_id,
    :block_id,
    :module_id,
    :global_set_id,
    :menu_item_id,
    :link_text,
    :link_target_blank,
    :link_type,
    # ignored
    :block,
    :id,
    :module,
    :creator,
    :creator_id,
    :updated_by,
    :updated_by_id,
    :edited_at,
    :file,
    :image,
    :video,
    :gallery,
    :form,
    :palette,
    :identifier,
    :page,
    :global_set,
    :table_template,
    :table_row,
    :menu_item,
    :__struct__,
    :__meta__
  ]

  def reapply_vars(_module, module_vars, vars) do
    vars_by_key = Map.new(module_vars, &{&1.key, &1})

    Enum.map(vars, fn
      %Changeset{data: %{key: var_key}} = var ->
        var_src = Map.get(vars_by_key, var_key, %{})
        attrs_to_take = Map.keys(var_src) -- @protected_and_ignored_var_attrs
        new_attrs = Map.take(var_src, attrs_to_take)

        var
        |> Changeset.change(new_attrs)
        |> FollowLinkDefault.follow()
    end)
  end

  # --- Struct Manipulation Utilities ---

  def add_uid_to_refs(nil), do: nil

  def add_uid_to_refs(refs) when is_list(refs) do
    Enum.map(refs, fn ref ->
      if Map.has_key?(ref, :uid) and ref.uid do
        ref
      else
        Map.put(ref, :uid, Utils.generate_uid())
      end
    end)
  end

  def add_uid_to_refs(changeset) do
    refs = Changeset.get_assoc(changeset, :refs)
    updated_refs = add_uid_to_ref_changesets(refs)
    Changeset.put_assoc(changeset, :refs, updated_refs)
  end

  @doc """
  Forces new UIDs for all refs in the list.

  Used when syncing module refs to blocks - each block instance needs
  its own unique UID, not the module template's UID.
  """
  def force_new_uids_for_refs(refs) when is_list(refs) do
    Enum.map(refs, fn ref ->
      Map.put(ref, :uid, Utils.generate_uid())
    end)
  end

  def add_uid_to_ref_changesets(nil), do: nil

  def add_uid_to_ref_changesets(refs) when is_list(refs) do
    Enum.reduce(refs, [], fn ref, acc ->
      updated_ref =
        if Changeset.get_field(ref, :uid) do
          ref
        else
          ref
          |> Changeset.put_change(:uid, Utils.generate_uid())
          |> Map.put(:action, :insert)
        end

      [updated_ref | acc]
    end)
  end

  def remove_pk_from_vars(nil), do: nil
  def remove_pk_from_vars([]), do: []

  # The copy is a new row: a colour value stored before values were checked
  # is left empty rather than refused (`Brando.Color.clear_invalid_var/1`),
  # and an empty link starts on its default tab (`FollowLinkDefault.put/1`).
  def remove_pk_from_vars(vars) when is_list(vars) do
    Enum.map(vars, fn var ->
      var
      |> Map.merge(%{id: nil, module_id: nil, block_id: nil})
      |> Brando.Color.clear_invalid_var()
      |> FollowLinkDefault.put()
      |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    end)
  end

  def remove_pk_from_refs(nil), do: nil
  def remove_pk_from_refs([]), do: []

  def remove_pk_from_refs(refs) when is_list(refs) do
    Enum.map(refs, &Map.merge(&1, %{id: nil, module_id: nil}))
  end

  def reject_deleted([]), do: []
  def reject_deleted(nil), do: []

  def reject_deleted(block_changesets, root \\ true) when is_list(block_changesets) do
    Enum.reduce(block_changesets, [], fn
      # `marked_as_deleted` needs no clause of its own: `ChangesetRunner`
      # rewrites it to `action: :delete` (or `:ignore`, which `put_assoc` skips)
      # before this runs.
      %{action: :delete}, acc ->
        acc

      %{action: :replace}, acc ->
        acc

      block_cs, acc ->
        if root do
          sub_cs = Changeset.get_assoc(block_cs, :block)
          children = Changeset.get_assoc(sub_cs, :children)
          processed_children = reject_deleted(children, false)
          updated_sub_cs = Changeset.put_assoc(sub_cs, :children, processed_children)
          updated_entry_block_cs = Changeset.put_assoc(block_cs, :block, updated_sub_cs)
          [updated_entry_block_cs | acc]
        else
          children = Changeset.get_assoc(block_cs, :children)
          processed_children = reject_deleted(children, false)
          updated_block_cs = Changeset.put_assoc(block_cs, :children, processed_children)
          [updated_block_cs | acc]
        end
    end)
    |> Enum.reverse()
  end

  @doc """
  Strip editor-only render artifacts from block changesets before save.

  While live preview is open, the editor stamps annotated `rendered_html` +
  `rendered_at` into every block changeset. Nothing reads the persisted
  column back — the frontend serves the entry's own `rendered_*` fields —
  but the stray changes make every block row dirty, turning a one-block
  edit into an UPDATE per block. Deleting the changes lets `put_assoc`
  skip untouched blocks entirely.
  """
  def strip_render_artifacts(block_changesets, root \\ true)
  def strip_render_artifacts([], _root), do: []
  def strip_render_artifacts(nil, _root), do: []

  def strip_render_artifacts(block_changesets, root) when is_list(block_changesets) do
    Enum.map(block_changesets, &strip_render_artifacts_from_changeset(&1, root))
  end

  defp strip_render_artifacts_from_changeset(block_changeset, false),
    do: strip_block_render_changes(block_changeset)

  defp strip_render_artifacts_from_changeset(block_changeset, true) do
    case Changeset.get_change(block_changeset, :block) do
      nil -> block_changeset
      block -> Changeset.put_assoc(block_changeset, :block, strip_block_render_changes(block))
    end
  end

  defp strip_block_render_changes(block_cs) do
    block_cs =
      block_cs
      |> Changeset.delete_change(:rendered_html)
      |> Changeset.delete_change(:rendered_at)

    case Changeset.get_change(block_cs, :children) do
      nil ->
        block_cs

      children ->
        # :replace/:delete entries must not be fed back to put_assoc (Ecto
        # raises) — their absence from the new list is what expresses the
        # deletion; Ecto re-derives the replaces from data.
        kept =
          children
          |> Enum.reject(&(&1.action in [:replace, :delete]))
          |> strip_render_artifacts(false)

        Changeset.put_assoc(block_cs, :children, kept)
    end
  end

  # --- Preload Strategy ---

  @doc """
  Counts an entry's blocks in each of its block fields, nested blocks
  included: the number of blocks the block editor renders. Returns a map of
  field name to count, empty for a schema without blocks.

  The entry form reads it before the block preloads run, to decide whether
  the blocks render with the rest of the form or after it, and to say how many
  are on their way. One recursive query per block field.
  """
  def count_entry_blocks_by_field(schema, entry_id) do
    if schema.has_trait(Brando.Trait.Blocks) do
      Map.new(schema.__blocks_fields__(), fn %{name: assoc_name} ->
        join_schema = Module.concat([schema, assoc_name |> to_string() |> Macro.camelize()])
        {assoc_name, count_block_tree(join_schema, entry_id)}
      end)
    else
      %{}
    end
  end

  @doc "All of an entry's blocks, every field and level, see `count_entry_blocks_by_field/2`."
  def count_entry_blocks(schema, entry_id) do
    schema
    |> count_entry_blocks_by_field(entry_id)
    |> Map.values()
    |> Enum.sum()
  end

  defp count_block_tree(join_schema, entry_id) do
    roots = from(j in join_schema, where: j.entry_id == ^entry_id, select: %{id: j.block_id})

    descendants =
      from(b in Block,
        join: tree in "entry_block_tree",
        on: b.parent_id == tree.id,
        select: %{id: b.id}
      )

    from(tree in "entry_block_tree", select: count())
    |> recursive_ctes(true)
    |> with_cte("entry_block_tree", as: ^union_all(roots, ^descendants))
    |> Repo.one()
  end

  @doc """
  Returns a list of preloads for a schema if it has the Blocks trait.
  """
  defdelegate preloads_for(schema), to: BlockPreloads, as: :for_schema

  @doc """
  Loads and stitches the complete descendant trees for the given parent IDs.
  """
  defdelegate preload_child_trees(parent_ids), to: BlockPreloads

  # --- Block Duplication ---

  @doc """
  Duplicates a block from its changeset.

  Generates a new UID, clears database IDs, and recursively duplicates
  all associations (vars, refs, table_rows, children).

  ## Options

    * `:user_id` - required, the creator ID for the duplicated block
    * `:sequence` - optional, defaults to 0
    * `:uid` - optional, auto-generated if not provided
    * `:source` - optional, the entry-block schema the copy now belongs to.
      Required when the copy lands under a *different* schema than the
      original (pasting a block from a page into a project): `source` names
      the join table a block is reachable through, so a stale one makes the
      block look orphaned to `list_orphaned_blocks/0`. Applied recursively to
      children. Omit to keep the original's source.
  """
  def duplicate_block(block_cs, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    sequence = Keyword.get(opts, :sequence, 0)
    block = Changeset.apply_changes(block_cs)
    mapping = Keyword.get_lazy(opts, :uid_mapping, fn -> Brando.Content.BlockSlots.uid_mapping(block) end)
    uid = Keyword.get(opts, :uid, Map.fetch!(mapping, block.uid))
    mapping = Map.put(mapping, block.uid, uid)

    children = Changeset.get_assoc(block_cs, :children, :struct)
    vars = Changeset.get_assoc(block_cs, :vars, :struct)
    table_rows = Changeset.get_assoc(block_cs, :table_rows, :struct)
    refs = Changeset.get_assoc(block_cs, :refs, :struct)
    {vars, table_rows} = Brando.Content.VarGuard.with_definition_types(block, vars, table_rows)

    block_cs
    |> Changeset.apply_changes()
    |> Map.merge(%{
      id: nil,
      uid: uid,
      sync_uid: nil,
      sequence: sequence,
      creator_id: user_id,
      parent_id: nil,
      slot_remap: nil,
      children: [],
      vars: [],
      table_rows: [],
      refs: []
    })
    |> maybe_put_source(Keyword.get(opts, :source))
    |> Changeset.change()
    |> duplicate_vars(vars, user_id)
    |> duplicate_table_rows(table_rows, user_id)
    |> duplicate_refs(refs, user_id)
    |> duplicate_children(children, user_id, Keyword.get(opts, :source), mapping)
    |> remap_footnote_markers(mapping)
    |> Map.put(:action, :insert)
  end

  defp maybe_put_source(block, nil), do: block
  defp maybe_put_source(block, source), do: Map.put(block, :source, source)

  def duplicate_children(changeset, children, current_user_id, source \\ nil, mapping \\ nil) do
    duplicated_children =
      Enum.with_index(children, fn child, sequence ->
        child
        |> Changeset.change()
        |> duplicate_block(
          user_id: current_user_id,
          sequence: sequence,
          source: source,
          uid_mapping: mapping || Brando.Content.BlockSlots.uid_mapping(child)
        )
      end)

    Changeset.put_assoc(changeset, :children, duplicated_children)
  end

  defp remap_footnote_markers(changeset, mapping) do
    changeset
    |> Changeset.update_change(:refs, fn refs -> Enum.map(refs, &remap_ref_footnote_markers(&1, mapping)) end)
    |> Changeset.update_change(:vars, fn vars -> Enum.map(vars, &remap_var_footnote_markers(&1, mapping)) end)
  end

  defp remap_ref_footnote_markers(ref, mapping) do
    case Changeset.get_field(ref, :data) do
      %{type: "text", data: data} = block ->
        text = Brando.Content.BlockSlots.remap_markers(data.text, mapping)
        Changeset.put_change(ref, :data, %{block | data: %{data | text: text}})

      _ ->
        ref
    end
  end

  defp remap_var_footnote_markers(var, mapping) do
    if Changeset.get_field(var, :type) in [:rich_text, :html] do
      value = Brando.Content.BlockSlots.remap_markers(Changeset.get_field(var, :value), mapping)
      Changeset.put_change(var, :value, value)
    else
      var
    end
  end

  @doc """
  Duplicates a single child block struct.

  Wraps the struct in a changeset and delegates to `duplicate_block/2`.
  """
  def duplicate_child(child_struct, current_user_id) do
    child_struct
    |> Changeset.change()
    |> duplicate_block(user_id: current_user_id)
  end

  def duplicate_vars(changeset, %Ecto.Association.NotLoaded{}, _) do
    require Logger

    Logger.error("""

    duplicate_vars ——

    vars NOT LOADED. This should not happen.

    #{inspect(changeset, pretty: true, width: 0)}

    """)

    changeset
  end

  def duplicate_vars(changeset, vars, current_user_id) do
    duplicated_vars = Enum.map(vars, &duplicate_var(&1, current_user_id))
    Changeset.put_assoc(changeset, :vars, duplicated_vars)
  end

  def duplicate_var(var, current_user_id) do
    var
    |> Map.merge(%{id: nil, block_id: nil})
    |> Brando.Color.clear_invalid_var()
    |> Brando.Content.Var.ValidateValue.clear_invalid()
    |> clone_ref_gallery(current_user_id)
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    |> Var.changeset(%{
      creator_id: current_user_id,
      sequence: var.sequence
    })
    |> Map.put(:action, :insert)
  end

  def duplicate_table_rows(changeset, table_rows, user_id) do
    duplicated_table_rows = Enum.map(table_rows, &duplicate_table_row(&1, user_id))
    Changeset.put_assoc(changeset, :table_rows, duplicated_table_rows)
  end

  def duplicate_table_row(table_row_struct, user_id) do
    vars = table_row_struct.vars

    table_row_struct
    |> Map.merge(%{id: nil, block_id: nil, vars: []})
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    |> Changeset.change()
    |> Map.put(:action, :insert)
    |> duplicate_vars(vars, user_id)
  end

  def duplicate_refs(changeset, %Ecto.Association.NotLoaded{}, _) do
    require Logger

    Logger.error("""

    duplicate_refs ——

    refs NOT LOADED. This should not happen.

    #{inspect(changeset, pretty: true, width: 0)}

    """)

    changeset
  end

  def duplicate_refs(changeset, refs, current_user_id) do
    duplicated_refs = Enum.map(refs, &duplicate_ref(&1, current_user_id))
    Changeset.put_assoc(changeset, :refs, duplicated_refs)
  end

  def duplicate_ref(ref, current_user_id) do
    ref
    |> Map.merge(%{id: nil, block_id: nil, module_id: nil})
    |> clone_ref_gallery(current_user_id)
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    |> Changeset.change(%{uid: Utils.generate_uid()})
    |> Map.put(:action, :insert)
  end

  # Images, videos and files are library assets, shared by reference — but a
  # gallery is *owned* by the ref that points at it. Leaving the copy on the
  # original's `gallery_id` means adding or removing media on the copy edits
  # the block it was copied from, which is at its most surprising when the two
  # blocks live in different entries (copy/paste across documents).
  #
  # The new row is written here rather than `put_assoc`ed onto the ref because
  # the block editor's op store drops belongs_to associations from a new
  # block's param snapshot (`BlockField.Ops.struct_to_params/1` keeps only the
  # owned trees) — only the `gallery_id` field survives to the save. Writing
  # the id AND the loaded struct onto the ref's *data* keeps both the save and
  # the editor's own gallery mutations (which read `gallery.id` back off the
  # loaded assoc) pointed at the copy.
  # Refs and gallery vars both own their gallery.
  defp clone_ref_gallery(%{gallery_id: nil} = ref, _user_id), do: ref

  defp clone_ref_gallery(%{gallery_id: gallery_id} = ref, user_id) do
    case Brando.Galleries.duplicate_gallery(gallery_id, user_id) do
      {:ok, gallery} ->
        %{ref | gallery_id: gallery.id, gallery: gallery}

      {:error, reason} ->
        require Logger

        Logger.error("""

        duplicate_ref ——

        Failed to duplicate gallery ##{inspect(gallery_id)}: #{inspect(reason)}.
        The copied ref keeps the original gallery, which means the two blocks
        now share it.

        """)

        ref
    end
  end

  defp clone_ref_gallery(ref, _user_id), do: ref
end
