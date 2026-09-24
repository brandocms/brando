defmodule Brando.Translations.Sync do
  @moduledoc """
  Computes a synchronized translation's pending version. Pure: the inputs are
  loaded entries, nothing is read or written.

  Both entries are first flattened into `{path, class, value}` rows:

    * `:text` — language-specific text (titles, block text, captions, alt text)
    * `:shared` — media selections and `source_controlled_fields`
    * `:local` — other values; copied once, then owned by each language
    * `:structure` — membership and order of blocks, refs, vars and rows

  The payload is built from the target: matched items keep their ids and
  language-specific values, take shared values from the source, and follow the
  source's order and nesting. Items only in the source are copied in; items
  only in the target are dropped. Work is then read off the flattened rows:

    * a text path the target lacks → `:translate` (skipped when empty)
    * a text path whose source digest moved from the baseline → `:review`,
      unless the save was a minor correction
    * a shared path the target holds a different value for → `:shared_update`

  ## Matching

  | Item | Key |
  | --- | --- |
  | Block, at any depth | `sync_uid`, else `uid` |
  | Ref | block + ref `name` (and data type) |
  | Var | block + var `key` (and type) |
  | Table row | block + row `sync_uid` |
  | Subform row | row `uid`; `Brando.Content.Var` rows by `key` |
  | Attribute / asset | field name |

  Subform collections whose rows have neither are left untouched, with a
  `skipped_relation` note. A gallery belongs to its ref, so a translation keeps
  its own gallery; its media and their order follow the source.
  """

  alias Brando.AI.Translation
  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Attributes
  alias Brando.Blueprint.Relations
  alias Brando.Content.Var
  alias Brando.Query.Mutations
  alias Brando.Villain.Blocks.GalleryBlock
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.VideoBlock

  @excluded_fields ~w(id language status publish_at inserted_at updated_at deleted_at
                      creator_id updated_by_id edited_at sequence)a
  @text_inputs [:text, :textarea, :rich_text]
  @media_fks [:image_id, :video_id, :file_id, :gallery_id]
  @media_assocs [:image, :video, :file, :gallery]

  @block_structure_fields ~w(type module_id module_origin container_id container_origin palette_id
                             palette_origin fragment_id slot_name slot_kind slot_module_set multi
                             datasource source active module_version)a

  @type row :: {String.t(), :text | :shared | :local | :structure, term()}

  @doc """
  Computes the pending version of `target` against `source`.

  `baseline` maps paths to the source digests this target was last synchronized
  with. Options: `:schema` (required), `:config` (defaults to the schema's
  `__translatable_config__/0`), `:minor` and `:identifiers`.

  `:identifiers` maps each source identifier id (`identifier_ids/2`) to the
  identifier of the same content in the target's language, or to nil when that
  translation does not exist yet. Links to content follow the source, mapped
  through this; an unmapped link is left out of the payload and raises an
  `:awaiting_translation` item until the translation exists. Without the
  option, links are copied as they are.

  Returns `payload` (the merged target), `work_items`
  (`%{path, kind, source_digest, minor}`), `notes`, the `baseline` to store,
  the payload's `paths`,
  the `fingerprint` of the payload and the `base_fingerprint` of the target.
  `changed?` is false when applying the payload would change nothing and no
  work was found.
  """
  def compute_pending(source, target, baseline, opts) do
    schema = Keyword.fetch!(opts, :schema)
    config = Keyword.get_lazy(opts, :config, fn -> schema.__translatable_config__() end)
    minor? = Keyword.get(opts, :minor, false)
    spec = spec(schema, config)

    {payload, notes} = merge(source, target, spec)
    {payload, awaiting} = resolve_identifiers(payload, spec, Keyword.get(opts, :identifiers))

    source_rows = flatten(source, spec)
    target_rows = flatten(target, spec)
    payload_rows = flatten(payload, spec)

    work_items = work_items(source_rows, target_rows, payload_rows, baseline || %{}, minor?) ++ awaiting
    fingerprint = fingerprint(payload_rows)
    base_fingerprint = fingerprint(target_rows)

    %{
      payload: payload,
      work_items: work_items,
      notes: notes,
      baseline: baseline(source_rows),
      paths: MapSet.new(payload_rows, &elem(&1, 0)),
      source_fingerprint: fingerprint(source_rows),
      fingerprint: fingerprint,
      base_fingerprint: base_fingerprint,
      changed?: fingerprint != base_fingerprint or work_items != []
    }
  end

  @doc "The baseline digests for `entry` as a source: one per text and shared path."
  def baseline_for(entry, schema, config \\ nil) do
    config = config || schema.__translatable_config__()
    entry |> flatten(spec(schema, config)) |> baseline()
  end

  @doc "Flattens an entry into `{path, class, value}` rows, in document order."
  def flatten_entry(entry, schema, config \\ nil) do
    flatten(entry, spec(schema, config || schema.__translatable_config__()))
  end

  @doc "The ids of every identifier `entry` links to, from blocks and var relations."
  def identifier_ids(entry, schema, config \\ nil) do
    spec = spec(schema, config || schema.__translatable_config__())

    block_ids =
      Enum.flat_map(spec.blocks_fields, fn field ->
        entry |> Map.get(field) |> loaded() |> Enum.flat_map(&block_identifier_ids(&1.block))
      end)

    var_ids = spec |> var_relations() |> Enum.flat_map(&(entry |> Map.get(&1) |> loaded())) |> var_identifier_ids()
    Enum.uniq(block_ids ++ var_ids)
  end

  defp block_identifier_ids(block) do
    Enum.map(loaded(block.block_identifiers), & &1.identifier_id) ++
      var_identifier_ids(loaded(block.vars) ++ Enum.flat_map(loaded(block.table_rows), &loaded(&1.vars))) ++
      Enum.flat_map(loaded(block.children), &block_identifier_ids/1)
  end

  defp var_identifier_ids(vars), do: for(%{identifier_id: id} <- vars, id, do: id)

  defp var_relations(spec), do: for(%{key: :key, name: name} <- spec.subforms, do: name)

  @doc "A short, stable digest of any term."
  def digest(term) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(term, [:deterministic]))
    |> binary_part(0, 12)
    |> Base.url_encode64(padding: false)
  end

  # --- Spec -------------------------------------------------------------------

  defp spec(schema, config) do
    attributes = Enum.map(Attributes.__attributes__(schema), & &1.name)
    text_fields = Translation.translatable_text_fields(schema)
    source_controlled = config.source_controlled_fields

    assets =
      for %{type: type, name: name} <- Assets.__assets__(schema), type in [:image, :file, :video, :gallery], do: name

    relations = Relations.__relations__(schema)

    shared_relations =
      for %{type: :belongs_to, name: name} <- relations, name in source_controlled, do: name

    fields =
      Enum.flat_map(attributes -- @excluded_fields, fn name ->
        cond do
          String.starts_with?(to_string(name), "rendered_") -> []
          name in source_controlled -> [{name, :shared}]
          name in text_fields -> [{name, :text}]
          true -> [{name, :local}]
        end
      end)

    blocks_fields =
      if function_exported?(schema, :__blocks_fields__, 0),
        do: Enum.map(schema.__blocks_fields__(), &:"entry_#{&1.name}"),
        else: []

    %{
      schema: schema,
      fields: fields,
      belongs_to: Enum.uniq(assets ++ shared_relations),
      blocks_fields: blocks_fields,
      subforms: subforms(schema, relations)
    }
  end

  defp subforms(schema, relations) do
    subform_text = subform_text_fields(schema)

    for %{type: type, name: name, opts: opts} <- relations,
        type in [:has_many, :embeds_many],
        type == :embeds_many or Map.get(opts, :cast) == true,
        is_atom(opts[:module]) and opts[:module] != :blocks do
      module = opts[:module]

      key =
        cond do
          module == Var -> :key
          :uid in module.__schema__(:fields) -> :uid
          true -> nil
        end

      related_key =
        case schema.__schema__(:association, name) do
          %{related_key: related_key} -> related_key
          _ -> nil
        end

      %{name: name, module: module, key: key, related_key: related_key, text: Map.get(subform_text, name, [])}
    end
  end

  defp subform_text_fields(schema) do
    case schema.__form__() do
      %{tabs: tabs} ->
        for tab <- tabs,
            fieldset <- tab.fields,
            %Brando.Blueprint.Forms.Subform{name: name, sub_fields: sub_fields} <- fieldset.fields,
            into: %{} do
          {name,
           for(%Brando.Blueprint.Forms.Input{type: type, name: field} <- sub_fields, type in @text_inputs, do: field)}
        end

      _ ->
        %{}
    end
  end

  # --- Flatten ----------------------------------------------------------------

  defp flatten(entry, spec) do
    field_rows =
      Enum.map(spec.fields, fn {name, class} -> {to_string(name), class, Map.get(entry, name)} end)

    asset_rows =
      Enum.map(spec.belongs_to, fn name -> {to_string(name), :shared, Map.get(entry, :"#{name}_id")} end)

    block_rows =
      Enum.flat_map(spec.blocks_fields, fn field ->
        entry_blocks = loaded(Map.get(entry, field))
        blocks = Enum.map(entry_blocks, & &1.block)
        identities = identities(blocks)
        prefix = to_string(field)

        [
          {prefix, :structure, Enum.map(blocks, &identities[&1.uid])}
          | Enum.flat_map(blocks, &flatten_block(&1, prefix, identities))
        ]
      end)

    subform_rows = Enum.flat_map(spec.subforms, &flatten_subform(entry, &1))

    field_rows ++ asset_rows ++ block_rows ++ subform_rows
  end

  # Paths are `<field>/<identity>` at every depth: nesting is recorded in the
  # parent's structure row, so moving a block does not change its paths.
  defp flatten_block(block, parent_prefix, identities) do
    prefix = "#{parent_prefix}/#{identities[block.uid]}"
    children = loaded(block.children)
    refs = loaded(block.refs)
    vars = loaded(block.vars)
    rows = loaded(block.table_rows)
    row_ids = row_identities(rows)

    structure =
      block
      |> Map.take(@block_structure_fields)
      |> Map.merge(%{
        children: Enum.map(children, &identities[&1.uid]),
        refs: Enum.map(refs, &{&1.name, ref_type(&1)}),
        vars: Enum.map(vars, &{&1.key, &1.type}),
        rows: Enum.map(rows, &row_ids[&1])
      })

    identifiers = {prefix <> "/identifiers", :shared, Enum.map(loaded(block.block_identifiers), & &1.identifier_id)}

    [{prefix, :structure, structure}, identifiers] ++
      Enum.flat_map(refs, &flatten_ref(&1, prefix)) ++
      Enum.flat_map(vars, &flatten_var(&1, "#{prefix}/vars")) ++
      Enum.flat_map(rows, fn row ->
        Enum.flat_map(loaded(row.vars), &flatten_var(&1, "#{prefix}/rows/#{row_ids[row]}/vars"))
      end) ++
      flatten_identifier_metas(block, prefix) ++
      Enum.flat_map(children, &flatten_block(&1, parent_prefix, identities))
  end

  defp flatten_ref(ref, block_prefix) do
    prefix = "#{block_prefix}/refs/#{ref.name}"
    media = {prefix <> "/media", :shared, Map.take(ref, [:image_id, :video_id, :file_id])}

    data_rows =
      case ref.data do
        %wrapper{data: data} ->
          cond do
            wrapper in Translation.text_ref_wrapper_types() ->
              [{prefix <> "/text", :text, Map.get(data, :text)}]

            wrapper == PictureBlock ->
              for field <- [:title, :credits, :alt], do: {"#{prefix}/#{field}", :text, Map.get(data, field)}

            wrapper == VideoBlock ->
              [{prefix <> "/title", :text, Map.get(data, :title)}]

            wrapper == GalleryBlock ->
              flatten_gallery(ref, data, prefix)

            true ->
              [{prefix <> "/data", :local, data}]
          end

        _ ->
          []
      end

    [media | data_rows]
  end

  defp flatten_gallery(ref, data, prefix) do
    overrides =
      for override <- data.gallery_object_overrides || [],
          key = Brando.Villain.Blocks.GalleryObjectOverride.media_key(override),
          key != nil,
          field <- [:title, :credits, :alt] do
        {"#{prefix}/gallery/#{media_key_string(key)}/#{field}", :text, Map.get(override, field)}
      end

    [{prefix <> "/gallery", :shared, gallery_media(ref)} | overrides]
  end

  defp gallery_media(%{gallery: %{gallery_objects: objects}}) when is_list(objects) do
    Enum.map(objects, fn object -> {object.image_id, object.video_id} end)
  end

  defp gallery_media(_), do: nil

  defp media_key_string({type, id}), do: "#{type || "any"}:#{id}"

  defp flatten_var(var, parent_prefix) do
    prefix = "#{parent_prefix}/#{var.key}"
    media = {prefix <> "/media", :shared, Map.take(var, [:identifier_id | @media_fks])}

    value =
      cond do
        var.type in Translation.translatable_var_types() -> {prefix <> "/value", :text, var.value}
        var.type == :link -> {prefix <> "/link_text", :text, var.link_text}
        true -> {prefix <> "/value", :local, Map.take(var, [:value, :value_boolean])}
      end

    [media, value]
  end

  defp flatten_identifier_metas(%{identifier_metas: metas}, prefix) when is_map(metas) do
    for {identifier, fields} <- Enum.sort(metas), is_map(fields), {field, value} <- Enum.sort(fields) do
      {"#{prefix}/identifier_metas/#{identifier}/#{field}", :text, value}
    end
  end

  defp flatten_identifier_metas(_, _), do: []

  defp flatten_subform(_entry, %{key: nil}), do: []

  defp flatten_subform(entry, %{name: name, key: :key}) do
    vars = loaded(Map.get(entry, name))
    [{to_string(name), :structure, Enum.map(vars, & &1.key)} | Enum.flat_map(vars, &flatten_var(&1, to_string(name)))]
  end

  defp flatten_subform(entry, %{name: name, key: key, text: text, module: module, related_key: related_key}) do
    rows = loaded(Map.get(entry, name))
    fields = module.__schema__(:fields) -- [:id, key, related_key, :sequence, :inserted_at, :updated_at]

    [
      {to_string(name), :structure, Enum.map(rows, &Map.get(&1, key))}
      | Enum.flat_map(rows, fn row ->
          for field <- fields do
            class = if field in text, do: :text, else: :local
            {"#{name}/#{Map.get(row, key)}/#{field}", class, Map.get(row, field)}
          end
        end)
    ]
  end

  # --- Merge ------------------------------------------------------------------

  defp merge(source, target, spec) do
    payload =
      Enum.reduce(spec.fields, target, fn
        {name, :shared}, acc -> Map.put(acc, name, Map.get(source, name))
        _, acc -> acc
      end)

    payload =
      Enum.reduce(spec.belongs_to, payload, fn name, acc ->
        acc
        |> Map.put(:"#{name}_id", Map.get(source, :"#{name}_id"))
        |> Map.put(name, Map.get(source, name))
      end)

    {payload, block_notes} =
      Enum.reduce(spec.blocks_fields, {payload, []}, fn field, {acc, notes} ->
        {entry_blocks, field_notes} = merge_entry_blocks(Map.get(source, field), Map.get(target, field), target)
        {Map.put(acc, field, entry_blocks), notes ++ field_notes}
      end)

    {payload, subform_notes} =
      Enum.reduce(spec.subforms, {payload, []}, fn subform, {acc, notes} ->
        case merge_subform(source, target, subform) do
          {:ok, rows} -> {Map.put(acc, subform.name, rows), notes}
          :skipped -> {acc, notes ++ [%{"kind" => "skipped_relation", "path" => to_string(subform.name)}]}
        end
      end)

    {payload, block_notes ++ subform_notes}
  end

  defp merge_entry_blocks(source_entry_blocks, target_entry_blocks, target) do
    source_entry_blocks = loaded(source_entry_blocks)
    target_entry_blocks = loaded(target_entry_blocks)

    source_ids = identities(Enum.map(source_entry_blocks, & &1.block))
    target_blocks = Enum.map(target_entry_blocks, & &1.block)
    target_ids = identities(target_blocks)
    target_index = index_blocks(target_blocks, target_ids)
    target_joins = Map.new(target_entry_blocks, &{target_ids[&1.block.uid], &1})
    ctx = %{source_ids: source_ids, target_index: target_index}

    {entry_blocks, notes} =
      Enum.map_reduce(source_entry_blocks, [], fn source_join, notes ->
        identity = source_ids[source_join.block.uid]
        {block, block_notes} = merge_block(source_join.block, ctx)

        join =
          case target_joins[identity] do
            nil ->
              %{source_join | id: nil, entry_id: target.id, block_id: nil}
              |> put_in([Access.key(:__meta__), Access.key(:state)], :built)

            target_join ->
              target_join
          end

        {%{join | sequence: source_join.sequence, block: block}, notes ++ block_notes}
      end)

    {entry_blocks, notes}
  end

  defp merge_block(source_block, ctx) do
    identity = ctx.source_ids[source_block.uid]
    source_children = loaded(source_block.children)

    {children, child_notes} =
      Enum.map_reduce(source_children, [], fn child, notes ->
        {merged, merged_notes} = merge_block(child, ctx)
        {merged, notes ++ merged_notes}
      end)

    case ctx.target_index[identity] do
      nil ->
        block =
          %{source_block | children: []}
          |> Mutations.duplicate_block(true)
          |> Map.merge(%{sync_uid: identity, children: children})

        {block, child_notes}

      target_block ->
        refs = merge_refs(loaded(source_block.refs), loaded(target_block.refs))

        block =
          target_block
          |> Map.merge(Map.take(source_block, @block_structure_fields))
          |> Map.merge(%{
            sequence: source_block.sequence,
            children: children,
            refs: refs,
            block_identifiers: Enum.map(loaded(source_block.block_identifiers), &new_block_identifier/1),
            vars: merge_vars(loaded(source_block.vars), loaded(target_block.vars)),
            table_rows: merge_rows(loaded(source_block.table_rows), loaded(target_block.table_rows))
          })

        {block, child_notes}
    end
  end

  defp merge_refs(source_refs, target_refs) do
    target_by_name = Map.new(target_refs, &{{&1.name, ref_type(&1)}, &1})

    Enum.map(source_refs, fn source_ref ->
      case target_by_name[{source_ref.name, ref_type(source_ref)}] do
        nil ->
          clone_ref(source_ref)

        target_ref ->
          target_ref
          |> Map.merge(Map.take(source_ref, [:sequence, :active, :image_id, :image, :video_id, :video, :file_id, :file]))
          |> merge_gallery(source_ref)
      end
    end)
  end

  # The translation keeps its own gallery — galleries belong to their ref — but
  # its contents follow the source: same media, same order. Objects already in
  # it keep their ids; the rest are new. Captions and alt text live in the ref's
  # overrides and stay the translation's.
  defp merge_gallery(%{gallery: %{gallery_objects: target_objects} = gallery} = ref, %{
         gallery: %{gallery_objects: source_objects}
       })
       when is_list(target_objects) and is_list(source_objects) do
    by_media = Map.new(target_objects, &{{&1.image_id, &1.video_id}, &1})

    objects =
      source_objects
      |> Enum.with_index()
      |> Enum.map(fn {source_object, index} ->
        case by_media[{source_object.image_id, source_object.video_id}] do
          nil -> %{clone(source_object) | gallery_id: gallery.id, sequence: index}
          target_object -> %{target_object | sequence: index}
        end
      end)

    %{ref | gallery: %{gallery | gallery_objects: objects}}
  end

  defp merge_gallery(ref, _source_ref), do: ref

  defp clone_ref(ref) do
    ref
    |> Map.merge(%{id: nil, block_id: nil, uid: Brando.Utils.generate_uid(), inserted_at: nil, updated_at: nil})
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  defp merge_vars(source_vars, target_vars) do
    target_by_key = Map.new(target_vars, &{{&1.key, &1.type}, &1})

    Enum.map(source_vars, fn source_var ->
      case target_by_key[{source_var.key, source_var.type}] do
        nil ->
          clone(source_var)

        target_var ->
          Map.merge(
            target_var,
            Map.take(source_var, [:sequence, :identifier_id, :identifier | @media_fks ++ @media_assocs])
          )
      end
    end)
  end

  defp merge_rows(source_rows, target_rows) do
    source_ids = row_identities(source_rows)
    target_ids = row_identities(target_rows)
    target_by_id = Map.new(target_rows, &{target_ids[&1], &1})

    Enum.map(source_rows, fn source_row ->
      case target_by_id[source_ids[source_row]] do
        nil ->
          %{clone(source_row) | vars: Enum.map(loaded(source_row.vars), &clone/1)}

        target_row ->
          %{
            target_row
            | sequence: source_row.sequence,
              vars: merge_vars(loaded(source_row.vars), loaded(target_row.vars))
          }
      end
    end)
  end

  defp merge_subform(_source, _target, %{key: nil}), do: :skipped

  defp merge_subform(source, target, %{name: name, key: :key}) do
    {:ok, merge_vars(loaded(Map.get(source, name)), loaded(Map.get(target, name)))}
  end

  defp merge_subform(source, target, %{name: name, key: key, related_key: related_key}) do
    target_by_key = Map.new(loaded(Map.get(target, name)), &{Map.get(&1, key), &1})

    rows =
      Enum.map(loaded(Map.get(source, name)), fn source_row ->
        case target_by_key[Map.get(source_row, key)] do
          nil ->
            row = clone(source_row)
            if related_key, do: Map.put(row, related_key, target.id), else: row

          target_row ->
            if Map.has_key?(source_row, :sequence),
              do: %{target_row | sequence: source_row.sequence},
              else: target_row
        end
      end)

    {:ok, rows}
  end

  defp new_block_identifier(block_identifier) do
    %{unload(block_identifier, :identifier) | id: nil, block_id: nil}
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  # --- Identifiers ------------------------------------------------------------

  # Every link in the payload was taken from the source, so each is replaced by
  # its target-language counterpart. One with no counterpart yet is left out,
  # and an `:awaiting_translation` item records where it belongs; the next sync
  # after that translation is created puts it in.
  defp resolve_identifiers(payload, _spec, nil), do: {payload, []}

  defp resolve_identifiers(payload, spec, map) do
    {payload, awaiting} =
      Enum.reduce(spec.blocks_fields, {payload, []}, fn field, {acc, awaiting} ->
        joins = loaded(Map.get(acc, field))
        ids = identities(Enum.map(joins, & &1.block))

        {joins, awaiting} =
          Enum.map_reduce(joins, awaiting, fn join, awaiting ->
            {block, awaiting} = resolve_block(join.block, "#{field}", ids, map, awaiting)
            {%{join | block: block}, awaiting}
          end)

        {Map.put(acc, field, joins), awaiting}
      end)

    Enum.reduce(var_relations(spec), {payload, awaiting}, fn name, {acc, awaiting} ->
      {vars, awaiting} = resolve_vars(loaded(Map.get(acc, name)), "#{name}", map, awaiting)
      {Map.put(acc, name, vars), awaiting}
    end)
  end

  defp resolve_block(block, field_prefix, ids, map, awaiting) do
    prefix = "#{field_prefix}/#{ids[block.uid]}"

    {block_identifiers, awaiting} =
      Enum.flat_map_reduce(loaded(block.block_identifiers), awaiting, fn row, awaiting ->
        case map[row.identifier_id] do
          nil -> {[], [awaiting_item("#{prefix}/identifiers/#{row.identifier_id}") | awaiting]}
          target_id -> {[%{unload(row, :identifier) | identifier_id: target_id}], awaiting}
        end
      end)

    {vars, awaiting} = resolve_vars(loaded(block.vars), prefix <> "/vars", map, awaiting)
    rows = loaded(block.table_rows)
    row_ids = row_identities(rows)

    {rows, awaiting} =
      Enum.map_reduce(rows, awaiting, fn row, awaiting ->
        {vars, awaiting} = resolve_vars(loaded(row.vars), "#{prefix}/rows/#{row_ids[row]}/vars", map, awaiting)
        {%{row | vars: vars}, awaiting}
      end)

    {children, awaiting} =
      Enum.map_reduce(loaded(block.children), awaiting, &resolve_block(&1, field_prefix, ids, map, &2))

    block = %{block | block_identifiers: block_identifiers, vars: vars, table_rows: rows, children: children}
    {block, awaiting}
  end

  defp resolve_vars(vars, prefix, map, awaiting) do
    Enum.map_reduce(vars, awaiting, fn
      %{identifier_id: nil} = var, awaiting ->
        {var, awaiting}

      %{identifier_id: source_id} = var, awaiting ->
        case map[source_id] do
          nil ->
            {%{unload(var, :identifier) | identifier_id: nil},
             [awaiting_item("#{prefix}/#{var.key}/identifier/#{source_id}") | awaiting]}

          target_id ->
            {%{unload(var, :identifier) | identifier_id: target_id}, awaiting}
        end
    end)
  end

  # The preloaded association is the source's; the id alone now says where the
  # link points.
  defp unload(%module{} = struct, field) do
    Map.put(struct, field, %Ecto.Association.NotLoaded{__field__: field, __owner__: module, __cardinality__: :one})
  end

  defp awaiting_item(path), do: %{path: path, kind: :awaiting_translation, source_digest: nil, minor: false}

  defp clone(%{__meta__: %Ecto.Schema.Metadata{}} = struct) do
    struct
    |> Map.put(:id, nil)
    |> put_in([Access.key(:__meta__), Access.key(:state)], :built)
  end

  defp clone(struct), do: struct

  # --- Identity ---------------------------------------------------------------

  # A block's identity is its `sync_uid`, or its `uid` when it has none or when
  # another block in the same tree already claimed the `sync_uid` — a copy made
  # by a path that did not reset it. Keyed by `uid`, which is unique.
  defp identities(blocks) do
    {ids, _seen} = walk_identities(blocks, {%{}, MapSet.new()})
    ids
  end

  defp walk_identities(blocks, acc) do
    Enum.reduce(blocks, acc, fn block, {ids, seen} ->
      candidate = block.sync_uid || block.uid
      identity = if MapSet.member?(seen, candidate), do: block.uid, else: candidate
      walk_identities(loaded(block.children), {Map.put(ids, block.uid, identity), MapSet.put(seen, identity)})
    end)
  end

  defp index_blocks(blocks, ids) do
    Enum.reduce(blocks, %{}, fn block, acc ->
      acc
      |> Map.put(ids[block.uid], block)
      |> Map.merge(index_blocks(loaded(block.children), ids))
    end)
  end

  defp row_identities(rows) do
    {ids, _} =
      rows
      |> Enum.with_index()
      |> Enum.reduce({%{}, MapSet.new()}, fn {row, index}, {ids, seen} ->
        candidate = row.sync_uid || "##{index}"
        identity = if MapSet.member?(seen, candidate), do: "##{index}", else: candidate
        {Map.put(ids, row, identity), MapSet.put(seen, identity)}
      end)

    ids
  end

  defp ref_type(%{data: %wrapper{}}), do: wrapper
  defp ref_type(_), do: nil

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(nil), do: []
  defp loaded(list) when is_list(list), do: list

  # --- Work -------------------------------------------------------------------

  defp work_items(source_rows, target_rows, payload_rows, baseline, minor?) do
    ctx = %{
      source: Map.new(source_rows, fn {path, _class, value} -> {path, value} end),
      target: Map.new(target_rows, fn {path, class, value} -> {path, {class, value}} end),
      baseline: baseline,
      minor?: minor?
    }

    Enum.flat_map(payload_rows, &work_item(&1, ctx))
  end

  defp work_item({path, :text, value}, ctx) do
    source_digest = digest(Map.get(ctx.source, path, value))

    cond do
      not Map.has_key?(ctx.target, path) and not blank?(value) -> [item(path, :translate, source_digest)]
      not Map.has_key?(ctx.target, path) or ctx.minor? -> []
      Map.has_key?(ctx.baseline, path) and ctx.baseline[path] != source_digest -> [item(path, :review, source_digest)]
      true -> []
    end
  end

  defp work_item({path, :shared, value}, ctx) do
    case ctx.target[path] do
      {:shared, ^value} -> []
      nil -> []
      _ -> [item(path, :shared_update, digest(value))]
    end
  end

  defp work_item(_row, _ctx), do: []

  defp item(path, kind, source_digest), do: %{path: path, kind: kind, source_digest: source_digest, minor: false}

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp baseline(rows) do
    for {path, class, value} <- rows, class in [:text, :shared], into: %{}, do: {path, digest(value)}
  end

  defp fingerprint(rows), do: digest(rows)
end
