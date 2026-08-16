defmodule Brando.Content.Blocks do
  @moduledoc """
  Block queries, cascade orchestration, entry rendering,
  module sync, and struct manipulation.

  Extracted from `Brando.Villain` to establish a clean boundary:
  Content owns data and orchestration, Villain owns rendering.
  """
  import Ecto.Query

  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.BlockPreloads
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Trait
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.Blocks, as: VillainBlocks
  alias Ecto.Changeset

  @type changeset :: Ecto.Changeset.t()
  @fragment_module Module.concat(["Brando", "Pages", "Fragment"])

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
    |> Brando.Repo.all()
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
    |> Brando.Repo.all()
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
          |> Brando.Repo.all()
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
  def list_block_ids_using_palette(palette_id) do
    query =
      from b in Block,
        select: b.id,
        where: b.palette_id == ^palette_id

    Brando.Repo.all(query)
  end

  @doc """
  Return list of all block IDs that have a ref using `gallery_id`
  """
  def list_block_ids_using_gallery(gallery_id) do
    query =
      from r in Ref,
        select: r.block_id,
        where: r.gallery_id == ^gallery_id and not is_nil(r.block_id)

    Brando.Repo.all(query)
  end

  @doc """
  Return list of all blocks using `identifier_id` through vars
  """
  def list_block_ids_using_identifier(identifier_id) do
    query =
      from b in Block,
        select: b.id,
        left_join: v in assoc(b, :vars),
        where: v.identifier_id == ^identifier_id

    Brando.Repo.all(query)
  end

  @doc """
  Return list of all blocks containing `data-identifier-id="ID"` in ref data (TipTap inline links)
  """
  def list_block_ids_with_identifier_in_refs(identifier_id) do
    # In JSONB text representation, quotes are escaped as \"
    search_term = "%data-identifier-id=\\\\\"#{identifier_id}\\\\\"%"

    query =
      from b in Block,
        select: b.id,
        left_join: r in assoc(b, :refs),
        where: fragment("CAST(? AS TEXT) LIKE ?", r.data, ^search_term)

    Brando.Repo.all(query)
  end

  @doc """
  Return list of all blocks using `module_id`
  """
  def list_block_ids_using_module(module_id) do
    query =
      from b in Block,
        select: b.id,
        where: b.module_id == ^module_id

    Brando.Repo.all(query)
  end

  @doc """
  Return list of all blocks using `fragment_id`
  """
  def list_block_ids_using_fragment(fragment_id) do
    query =
      from b in Block,
        select: b.id,
        where: b.fragment_id == ^fragment_id

    Brando.Repo.all(query)
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

  @doc """
  List all occurences of regex in blocks.
  """
  @spec list_block_ids_matching_regex(search_terms :: {atom, binary} | [{atom, binary}]) :: [any]
  def list_block_ids_matching_regex(search_terms) do
    org_query = from(b in Block, select: %{"id" => b.id})
    search_terms = (is_list(search_terms) && search_terms) || [search_terms]

    built_query =
      Enum.reduce(search_terms, org_query, fn {search_name, search_term}, query ->
        search_name_refs = to_string(search_name) <> "_refs"
        search_name_vars = to_string(search_name) <> "_vars"

        from(q in query,
          left_join: vars in assoc(q, :vars),
          left_join: refs in assoc(q, :refs),
          select_merge: %{
            ^search_name_refs =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(refs.data, :string),
                ^search_term
              ),
            ^search_name_vars =>
              fragment(
                "regexp_matches(?, ?, 'g')",
                type(vars.value, :string),
                ^search_term
              )
          },
          order_by: [asc: q.id]
        )
      end)

    built_query
    |> Brando.Repo.all()
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

    Brando.Repo.all(built_query)
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
  def render_entries_with_module_id(module_id) do
    module_id
    |> list_block_ids_using_module()
    |> sync_and_render_blocks(module_id)
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
  def render_entries_with_palette_id(palette_id) do
    palette_id
    |> list_block_ids_using_palette()
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
  Update identifier link URLs in refs and re-render all entries referencing the identifier.

  When an identifier's URL changes, this:
  1. Updates the `href` in all block refs containing `data-identifier-id="ID"`
  2. Re-renders all entries with blocks referencing the identifier (through vars or inline links)
  """
  def update_identifier_links_and_rerender(identifier_id, new_url) do
    update_identifier_links_in_refs(identifier_id, new_url)

    var_block_ids = list_block_ids_using_identifier(identifier_id)
    ref_block_ids = list_block_ids_with_identifier_in_refs(identifier_id)

    (var_block_ids ++ ref_block_ids)
    |> Enum.uniq()
    |> list_root_block_ids_by_source()
    |> list_entry_ids_for_root_blocks_by_source()
    |> enqueue_entry_map_for_render()
  end

  @doc """
  Update the href of identifier links in all refs that reference the given identifier.
  """
  def update_identifier_links_in_refs(identifier_id, new_url) do
    # In JSONB text representation, quotes are escaped as \"
    search_term = "%data-identifier-id=\\\\\"#{identifier_id}\\\\\"%"

    query =
      from r in Brando.Content.Ref,
        where: fragment("CAST(? AS TEXT) LIKE ?", r.data, ^search_term)

    refs = Brando.Repo.all(query)

    for ref <- refs do
      update_ref_identifier_link(ref, identifier_id, new_url)
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
            |> Brando.Repo.update()

          :unchanged ->
            :ok
        end

      _ ->
        :ok
    end
  end

  @doc """
  Update identifier link URLs in rich text fields across all schemas.

  Walks all Blueprint schemas that have `:rich_text` form inputs,
  searches for entries containing `data-identifier-id="ID"` in those fields,
  and updates the href to the new URL.
  """
  def update_identifier_links_in_rich_text_fields(identifier_id, new_url) do
    for module <- Brando.Content.Identifier.Registry.list_persistent_identifier_modules(:include_brando),
        field <- rich_text_fields_for(module) do
      source = module.__schema__(:source)
      field_str = to_string(field)
      id_str = to_string(identifier_id)
      qualified_source = qualified_source(module, source)
      quoted_field = quote_identifier(field_str)

      # Single UPDATE per table/field using regexp_replace
      # Pattern: href="..." followed by data-identifier-id="ID"
      Ecto.Adapters.SQL.query(
        Brando.repo(),
        """
        UPDATE #{qualified_source}
        SET #{quoted_field} = regexp_replace(
          #{quoted_field},
          '(href=")[^"]*("[^>]*?data-identifier-id="' || $1 || '")',
          '\\1' || $2 || '\\2',
          'g'
        )
        WHERE #{quoted_field} LIKE $3
        """,
        [id_str, new_url, "%data-identifier-id=\"#{id_str}\"%"]
      )
    end
  end

  defp rich_text_fields_for(module) do
    if function_exported?(module, :__rich_text_fields__, 0) do
      module.__rich_text_fields__()
    else
      []
    end
  end

  defp qualified_source(module, source) do
    case module.__schema__(:prefix) || Brando.Tenant.current_prefix() do
      nil -> quote_identifier(source)
      prefix -> Enum.join([quote_identifier(prefix), quote_identifier(source)], ".")
    end
  end

  defp quote_identifier(identifier) do
    ~s|"#{String.replace(identifier, "\"", "\"\"")}"|
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
  Look through all modules for `search_terms` and rerender all villains that
  use this module
  """
  @spec rerender_matching_modules({atom, binary} | [{atom, binary}]) :: any
  def rerender_matching_modules(search_terms) do
    case search_modules_for_regex(search_terms) |> Enum.map(& &1["id"]) do
      [] -> nil
      ids -> for id <- ids, do: render_entries_with_module_id(id)
    end
  end

  @doc """
  Enqueue an async cascade job that merges datasource + identifier cascade
  discovery and enqueues EntryRenderer jobs in the background.
  """
  def enqueue_entry_cascade(module, entry, identifier_id) do
    %{schema: to_string(module), entry_id: entry.id, identifier_id: identifier_id}
    |> Brando.Tenant.Job.attach()
    |> Brando.Worker.EntryCascade.new()
    |> Oban.insert()
  end

  @doc """
  Enqueues every entry in a schema-to-entry-ids map for rendering.
  """
  defdelegate enqueue_entry_map_for_render(entry_map), to: Brando.Content.RenderQueue, as: :enqueue_map

  @doc """
  Enqueues all `ids` for `schema` for rendering.
  """
  defdelegate enqueue_entries_for_render(schema, ids), to: Brando.Content.RenderQueue, as: :enqueue_many

  @doc """
  Enqueues one entry-rendering job.
  """
  defdelegate enqueue_entry_for_render(args), to: Brando.Content.RenderQueue, as: :enqueue

  # --- Entry Rendering Orchestration ---

  @doc """
  Render all entries for `schema`
  """
  def render_all_entries(schema) do
    entry_ids =
      Brando.Repo.all(
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
  """
  @spec render_entry(schema :: module, entry_id :: integer | binary) ::
          {:ok, map} | {:error, changeset}
  def render_entry(schema, id) do
    case Brando.Blueprint.EntryQuery.get(schema, id) do
      {:ok, entry} ->
        changeset =
          entry
          |> Changeset.change()
          |> render_all_block_fields_and_add_to_changeset(schema, entry)

        case Brando.Repo.update(changeset) do
          {:ok, %{__struct__: fragment_module} = fragment} when fragment_module == @fragment_module ->
            Brando.Cache.Query.evict({:ok, fragment})
            render_entries_with_fragment_id(fragment.id)
            {:ok, fragment}

          {:ok, result} ->
            Brando.Cache.Query.evict({:ok, result})
            {:ok, result}
        end

      {:error, _} = err ->
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
  end

  @doc """
  Renders all block fields for an entry and adds them to changeset
  """
  def render_all_block_fields_and_add_to_changeset(changeset, schema, entry) do
    Enum.reduce(schema.__blocks_fields__(), changeset, fn field, updated_changeset ->
      rendered_field = :"rendered_#{field.name}"
      rendered_at_field = :"rendered_#{field.name}_at"
      entry_blocks_field = :"entry_#{field.name}"
      entry_blocks = Map.get(entry, entry_blocks_field)
      rendered_html = Villain.parse(entry_blocks, entry)

      updated_changeset
      |> Changeset.put_change(rendered_field, rendered_html)
      |> update_rendered_at_field_if_changed(rendered_field, rendered_at_field)
    end)
  end

  defp update_rendered_at_field_if_changed(changeset, rendered_field, rendered_at_field) do
    if Changeset.get_change(changeset, rendered_field) do
      Changeset.put_change(
        changeset,
        rendered_at_field,
        DateTime.truncate(DateTime.utc_now(), :second)
      )
    else
      changeset
    end
  end

  # --- Module Sync ---

  @doc """
  Gets all blocks with `module_id` and reapply refs and vars, then saves them.
  Returns a list of all updated block ids.
  """
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

    Enum.reduce(blocks, [], fn block, acc ->
      updated_changeset = sync_module(block, module)
      Brando.Repo.update(updated_changeset)
      [block.id | acc]
    end)
    |> render_blocks()
  end

  @doc """
  Syncs a block's vars and refs with a module
  """
  def sync_module(block, module) do
    module_refs = module.refs
    module_ref_names = Enum.map(module_refs, & &1.name)
    changeset = Changeset.change(block)

    # strip away refs that are no longer in the module
    current_refs =
      changeset
      |> Changeset.get_assoc(:refs)
      |> Enum.filter(&(Changeset.get_field(&1, :name) in module_ref_names))

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
  end

  def sync_and_render_blocks(block_ids, module_id) do
    {:ok, module} =
      Content.get_module(%{
        matches: %{id: module_id},
        preload: [:vars, refs: Ref.preloads()]
      })

    {:ok, blocks} =
      Content.list_blocks(%{
        filter: %{ids: block_ids},
        preload: [:vars, refs: Ref.preloads()]
      })

    blocks
    |> Enum.reduce([], fn block, acc ->
      block
      |> sync_module(module)
      |> Brando.Repo.update()

      [block.id | acc]
    end)
    |> render_blocks()
  end

  def render_blocks(block_ids) do
    source_map = list_root_block_ids_by_source(block_ids)

    for {join_source, ids} <- source_map do
      {:assoc, %{queryable: schema}} = Map.get(join_source.__changeset__(), :entry)

      query =
        from js in join_source,
          where: js.block_id in ^ids,
          select: [js.entry_id, fragment("array_agg(?)", js.block_id)],
          group_by: js.entry_id

      grouped_block_ids = Brando.Repo.all(query)

      for {entry_id, block_ids} <- grouped_block_ids do
        {:ok, entry} = Brando.Blueprint.EntryQuery.get(schema, entry_id)

        {:ok, blocks} =
          Content.list_blocks(%{
            filter: %{ids: block_ids},
            preload: [:vars, :module]
          })

        Enum.each(blocks, &render_and_update_block(&1, entry))
      end
    end

    source_map
  end

  defp render_and_update_block(block, entry) do
    rendered_block = Villain.render_block(block, entry)

    changes = %{
      rendered_html: rendered_block,
      rendered_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    block
    |> Changeset.change(changes)
    |> Brando.Repo.update()
  end

  def reapply_refs(module, module_refs, refs) do
    refs_by_name = Map.new(module_refs, &{&1.name, &1})

    Enum.map(refs, fn
      %Changeset{data: %{name: ref_name}} = ref ->
        block_module =
          case Changeset.get_field(ref, :data) do
            %Changeset{} = data_cs ->
              data_cs.data.__struct__

            block_data ->
              block_data.__struct__
          end

        ref_src = Map.get(refs_by_name, ref_name)

        if ref_src == nil do
          raise """

          Ref #{ref_name} not found in module refs!

          Module: ##{module.id} [#{module.namespace}] #{module.name}

          #{inspect(module, pretty: true)}

          """
        end

        ref_target = apply_ref_principals(ref_src, ref)
        block_module.apply_ref(ref_src.data.__struct__, ref_src, ref_target)
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
    :file,
    :image,
    :video,
    :gallery,
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
        Changeset.change(var, new_attrs)
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

  def remove_pk_from_vars(vars) when is_list(vars) do
    Enum.map(vars, fn var ->
      var
      |> Map.merge(%{id: nil, module_id: nil, block_id: nil})
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
      # before this runs. The clause that used to sit here spelled it
      # `mark_as_deleted` and so never matched anything.
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
  Count the root blocks attached to an entry across all of the schema's
  block fields.

  A fast aggregate over the entry↔block join schemas — used by the form's
  loading overlay to tell the user how many blocks are on their way before
  the heavy preload pass runs.
  """
  def count_entry_blocks(schema, entry_id) do
    if schema.has_trait(Brando.Trait.Blocks) do
      Enum.reduce(schema.__blocks_fields__(), 0, fn %{name: assoc_name}, acc ->
        field_as_module =
          assoc_name
          |> to_string
          |> Macro.camelize()
          |> then(&:"#{&1}")

        join_schema = Module.concat([schema, field_as_module])
        acc + Brando.Repo.aggregate(from(j in join_schema, where: j.entry_id == ^entry_id), :count)
      end)
    else
      0
    end
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
  """
  def duplicate_block(block_cs, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    sequence = Keyword.get(opts, :sequence, 0)
    uid = Keyword.get(opts, :uid, Utils.generate_uid())

    children = Changeset.get_assoc(block_cs, :children, :struct)
    vars = Changeset.get_assoc(block_cs, :vars, :struct)
    table_rows = Changeset.get_assoc(block_cs, :table_rows, :struct)
    refs = Changeset.get_assoc(block_cs, :refs, :struct)

    block_cs
    |> Changeset.apply_changes()
    |> Map.merge(%{
      id: nil,
      uid: uid,
      sequence: sequence,
      creator_id: user_id,
      parent_id: nil,
      children: [],
      vars: [],
      table_rows: [],
      refs: []
    })
    |> Changeset.change()
    |> duplicate_vars(vars, user_id)
    |> duplicate_table_rows(table_rows, user_id)
    |> duplicate_refs(refs, user_id)
    |> duplicate_children(children, user_id)
    |> Map.put(:action, :insert)
  end

  def duplicate_children(changeset, children, current_user_id) do
    duplicated_children =
      Enum.map(children, fn child ->
        child
        |> Changeset.change()
        |> duplicate_block(user_id: current_user_id)
      end)

    Changeset.put_assoc(changeset, :children, duplicated_children)
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

  def duplicate_ref(ref, _current_user_id) do
    ref
    |> Map.merge(%{id: nil, block_id: nil, module_id: nil})
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
    |> Changeset.change(%{uid: Utils.generate_uid()})
    |> Map.put(:action, :insert)
  end
end
