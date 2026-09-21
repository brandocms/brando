defmodule Brando.Content.Transfer.EntryCodec do
  use Gettext, backend: Brando.Gettext
  @moduledoc false
  import Ecto.Query, only: [from: 2]
  alias Brando.Blueprint.{Attributes, Relations}
  alias Brando.Content.Transfer.{Catalog, Dependencies, Error, Portable}
  alias Brando.Content.Definition.Value
  alias Brando.Drafts.Params
  alias Brando.Repo

  @system ~w(id uid creator_id updated_by_id inserted_at updated_at edited_at deleted_at marked_as_deleted password password_confirmation password_hash)a
  @media %{
    Brando.Images.Image => "image",
    Brando.Files.File => "file",
    Brando.Videos.Video => "video",
    Brando.Galleries.Gallery => "gallery",
    Brando.Content.Identifier => "identifier",
    Brando.Content.Palette => "palette",
    Brando.Content.Module => "module",
    Brando.Content.ModuleSet => "module_set",
    Brando.Content.TableTemplate => "table_template",
    Brando.Pages.Fragment => "fragment"
  }

  def schema!(name) do
    schema =
      Brando.Authorization.Catalog.schema(name) ||
        Error.fail!(dgettext("content_transfer", "The entry's Blueprint is not registered on this site."))

    unless is_binary(schema.__schema__(:source)) && function_exported?(schema, :changeset, 5),
      do: Error.fail!(dgettext("content_transfer", "Only saved Blueprint entries can be transferred."))

    schema
  end

  def load!(name, id, actor, action \\ :read, opts \\ []) do
    schema = schema!(name)
    query = from(e in schema, where: e.id == ^Catalog.id!(id)) |> Catalog.scoped_query(schema, actor, action)
    query = if opts[:lock], do: from(e in query, lock: "FOR UPDATE"), else: query

    entry =
      Repo.one(query) || Error.fail!(dgettext("content_transfer", "The entry is no longer available in this workspace."))

    if Map.get(entry, :deleted_at), do: Error.fail!(dgettext("content_transfer", "The entry has been deleted."))
    Catalog.authorize!(actor, action, entry)
    preload(entry)
  end

  def preload(entry, depth \\ 0)

  def preload(_, depth) when depth > 20,
    do: Error.fail!(dgettext("content_transfer", "Owned entry content exceeds 20 nested levels."))

  def preload(entry, depth) do
    schema = entry.__struct__

    entry =
      if function_exported?(schema, :__blocks_fields__, 0),
        do: Repo.preload(entry, Brando.Content.BlockPreloads.for_schema(schema)),
        else: entry

    galleries =
      for name <- schema.__schema__(:associations),
          Map.get(schema.__schema__(:association, name), :related) == Brando.Galleries.Gallery,
          do: {name, :gallery_objects}

    entry = Repo.preload(entry, galleries)
    collections = for {name, _, _, :many} <- references(schema), do: name
    entry = Repo.preload(entry, collections)

    Enum.reduce(owned(schema), entry, fn {name, related, _owner_key}, acc ->
      acc = if name in schema.__schema__(:associations), do: Repo.preload(acc, name), else: acc

      value =
        case Map.get(acc, name) do
          nil -> nil
          values when is_list(values) -> Enum.map(values, &preload(&1, depth + 1))
          value -> preload(value, depth + 1)
        end

      _ = related
      Map.put(acc, name, value)
    end)
  end

  def blank(schema) do
    Enum.reduce(schema.__schema__(:associations), struct(schema), fn name, entry ->
      assoc = schema.__schema__(:association, name)
      Map.put(entry, name, if(assoc.cardinality == :many, do: [], else: nil))
    end)
  end

  def attributes(schema, owner_key \\ nil) do
    fields =
      if function_exported?(schema, :__naming__, 0),
        do: Enum.map(Attributes.__attributes__(schema), & &1.name),
        else: schema.__schema__(:fields)

    foreign_keys =
      for name <- schema.__schema__(:associations),
          %Ecto.Association.BelongsTo{owner_key: key} <- [schema.__schema__(:association, name)],
          do: key

    Enum.reject(
      fields,
      &(&1 in (@system ++ foreign_keys ++ schema.__schema__(:embeds) ++ [owner_key]) ||
          &1 in schema.__schema__(:virtual_fields) || String.starts_with?(to_string(&1), "rendered_"))
    )
  end

  def owned(schema) do
    declarations = if function_exported?(schema, :__naming__, 0), do: Relations.__relations__(schema), else: []

    declared =
      Enum.flat_map(declarations, fn rel ->
        cond do
          rel.opts[:module] == :blocks ->
            []

          rel.type in [:embeds_one, :embeds_many] ->
            embed = schema.__schema__(:embed, rel.name)
            [{rel.name, embed.related, nil}]

          rel.type == :entries || (rel.type in [:has_many, :has_one] && rel.opts[:cast]) ->
            assoc = schema.__schema__(:association, rel.name)
            [{rel.name, assoc.related, assoc.related_key}]

          rel.type == :belongs_to && rel.opts[:cast] && !Map.has_key?(@media, rel.opts[:module]) ->
            assoc = schema.__schema__(:association, rel.name)
            [{rel.name, assoc.related, nil}]

          true ->
            []
        end
      end)

    # Plain embedded schemas still have an Ecto-owned embed contract.
    embeds =
      for name <- schema.__schema__(:embeds),
          name not in Enum.map(declared, &elem(&1, 0)),
          do: {name, schema.__schema__(:embed, name).related, nil}

    declared ++ embeds
  end

  def references(schema, owner_key \\ nil) do
    owned_names = Enum.map(owned(schema), &elem(&1, 0))
    declarations = if function_exported?(schema, :__naming__, 0), do: Relations.__relations__(schema), else: []

    Enum.flat_map(schema.__schema__(:associations), fn name ->
      assoc = schema.__schema__(:association, name)

      cond do
        name in owned_names ->
          []

        match?(%Ecto.Association.BelongsTo{}, assoc) && assoc.owner_key not in (@system ++ [owner_key]) ->
          [{name, assoc.related, assoc.owner_key, :one}]

        match?(%Ecto.Association.ManyToMany{}, assoc) && Enum.any?(declarations, &(&1.name == name && &1.opts[:cast])) ->
          [{name, assoc.related, nil, :many}]

        true ->
          []
      end
    end)
  end

  def encode(entry, state, owner_key \\ nil, depth \\ 0)

  def encode(_, _, _, depth) when depth > 20,
    do: Error.fail!(dgettext("content_transfer", "Owned entry content exceeds 20 nested levels."))

  def encode(entry, state, owner_key, depth) do
    schema = entry.__struct__

    {attrs, state} =
      entry |> Map.take(attributes(schema, owner_key)) |> Params.snapshot() |> authored(&Portable.encode_values/2, state)

    {refs, state} =
      Enum.map_reduce(references(schema, owner_key), state, fn {name, related, key, cardinality}, acc ->
        values = if cardinality == :many, do: Repo.preload(entry, name) |> Map.fetch!(name), else: Map.get(entry, key)

        {tokens, acc} =
          if cardinality == :many do
            Enum.map_reduce(values, acc, fn record, acc -> reference(related, record.id, acc) end)
          else
            reference(related, values, acc)
          end

        {{to_string(name), tokens}, acc}
      end)

    {children, state} =
      Enum.map_reduce(owned(schema), state, fn {name, _, parent_key}, acc ->
        {value, acc} =
          case Map.get(entry, name) do
            nil -> {nil, acc}
            values when is_list(values) -> Enum.map_reduce(values, acc, &encode(&1, &2, parent_key, depth + 1))
            value -> encode(value, acc, parent_key, depth + 1)
          end

        {{to_string(name), value}, acc}
      end)

    {blocks, state} =
      Enum.map_reduce(Catalog.fields(schema), state, fn field, acc ->
        joins = Map.get(entry, field.association, [])
        {blocks, acc} = Enum.map_reduce(joins, acc, &Portable.encode(&1.block, &2))
        {{field.name, blocks}, acc}
      end)

    {%{"attributes" => attrs, "references" => Map.new(refs), "owned" => Map.new(children), "blocks" => Map.new(blocks)},
     state}
  end

  defp reference(_, nil, state), do: {nil, state}

  defp reference(schema, id, state) do
    if kind = @media[schema], do: Dependencies.add(kind, id, state), else: Dependencies.add_entry(schema, id, state)
  end

  def validate!(node, schema, dependencies, owner_key \\ nil, depth \\ 0)

  def validate!(_, _, _, _, depth) when depth > 20,
    do: Error.fail!(dgettext("content_transfer", "Owned entry content exceeds 20 nested levels."))

  def validate!(node, schema, dependencies, owner_key, depth) do
    Value.keys!(node, ~w(attributes references owned blocks), "entry content")
    Value.keys!(node["attributes"], Enum.map(attributes(schema, owner_key), &to_string/1), "entry attributes")
    refs = references(schema, owner_key)
    Value.keys!(node["references"], Enum.map(refs, &to_string(elem(&1, 0))), "entry relationships")

    Enum.each(refs, fn {name, related, _, cardinality} ->
      value = node["references"][to_string(name)]

      unless is_nil(value) || (cardinality == :many && is_list(value)) || (cardinality == :one && is_binary(value)),
        do: Error.fail!(dgettext("content_transfer", "Invalid entry relationship %{value1}.", value1: name))

      Enum.each(List.wrap(value), fn token ->
        dep =
          dependencies[token] ||
            Error.fail!(dgettext("content_transfer", "An entry relationship is missing from the bundle."))

        expected = @media[related] || "entry"

        unless dep["kind"] == expected && (expected != "entry" || dep["schema"] == to_string(related)),
          do:
            Error.fail!(
              dgettext("content_transfer", "The relationship %{value1} has an incompatible content type.", value1: name)
            )
      end)
    end)

    owned = owned(schema)
    Value.keys!(node["owned"], Enum.map(owned, &to_string(elem(&1, 0))), "owned entry content")

    Enum.each(owned, fn {name, related, parent_key} ->
      contract = schema.__schema__(:association, name) || schema.__schema__(:embed, name)
      value = node["owned"][to_string(name)]

      unless (contract.cardinality == :many && is_list(value)) ||
               (contract.cardinality == :one && (is_nil(value) || is_map(value))),
             do: Error.fail!(dgettext("content_transfer", "Invalid owned collection %{value1}.", value1: name))

      Enum.each(List.wrap(node["owned"][to_string(name)]), &validate!(&1, related, dependencies, parent_key, depth + 1))
    end)

    Value.keys!(node["blocks"], Enum.map(Catalog.fields(schema), & &1.name), "entry block fields")

    Enum.each(node["blocks"], fn {_, blocks} ->
      unless is_list(blocks), do: Error.fail!(dgettext("content_transfer", "Invalid entry block field."))
      Portable.validate_blocks!(blocks, dependencies)
    end)

    authored(
      node["attributes"],
      fn value, acc ->
        Portable.validate_values!(value, dependencies)
        {value, acc}
      end,
      nil
    )

    # Authored fields are complete snapshots. Never silently accept a truncated entry.
    unless Enum.sort(Map.keys(node["attributes"])) == Enum.sort(Enum.map(attributes(schema, owner_key), &to_string/1)) &&
             Enum.sort(Map.keys(node["references"])) == Enum.sort(Enum.map(refs, &to_string(elem(&1, 0)))) &&
             Enum.sort(Map.keys(node["owned"])) == Enum.sort(Enum.map(owned, &to_string(elem(&1, 0)))) &&
             Enum.sort(Map.keys(node["blocks"])) == Enum.sort(Enum.map(Catalog.fields(schema), & &1.name)),
           do:
             Error.fail!(
               dgettext(
                 "content_transfer",
                 "The entry fields differ from the destination Blueprint. Deploy the matching schema before importing."
               )
             )

    :ok
  end

  def block_fields(node) do
    Map.values(node["blocks"]) ++
      Enum.flat_map(node["owned"], fn {_, value} -> Enum.flat_map(List.wrap(value), &block_fields/1) end)
  end

  def decode(node, schema, bindings, actor, opts \\ []) do
    uids =
      Keyword.get_lazy(opts, :uids, fn ->
        node
        |> block_fields()
        |> List.flatten()
        |> Portable.walk(& &1["uid"])
        |> Map.new(&{&1, Brando.Utils.generate_uid()})
      end)

    {attrs, _} =
      authored(node["attributes"], fn value, acc -> {Portable.decode_values(value, bindings, uids), acc} end, nil)

    attrs =
      Enum.reduce(references(schema, opts[:owner_key]), attrs, fn {name, _related, key, cardinality}, params ->
        value = node["references"][to_string(name)]

        decoded =
          if cardinality == :many,
            do: Enum.map(value || [], &resolve!(bindings, &1).id),
            else: if(value, do: resolve!(bindings, value).id)

        if gallery_asset?(schema, name) do
          # Gallery asset changesets accept nested data, while other assets cast FKs.
          if value do
            gallery = resolve!(bindings, value)

            objects =
              if gallery.id && gallery.id > 0, do: Repo.preload(gallery, :gallery_objects).gallery_objects, else: []

            Map.put(params, to_string(name), %{
              "config_target" => gallery.config_target,
              "gallery_objects" =>
                Enum.map(objects, &(Params.snapshot(&1) |> Map.take(~w(image_id video_id config sequence))))
            })
          else
            Map.put(params, to_string(name), "")
          end
        else
          Map.put(params, to_string(key || name), decoded)
        end
      end)

    attrs =
      Enum.reduce(owned(schema), attrs, fn {name, related, parent_key}, params ->
        value = node["owned"][to_string(name)]

        decoded =
          case value do
            nil ->
              nil

            list when is_list(list) ->
              Enum.map(
                list,
                &decode(&1, related, bindings, actor, Keyword.merge(opts, uids: uids, owner_key: parent_key))
              )

            child ->
              decode(child, related, bindings, actor, Keyword.merge(opts, uids: uids, owner_key: parent_key))
          end

        Map.put(params, to_string(name), decoded)
      end)

    if opts[:without_blocks] do
      attrs
    else
      Enum.reduce(Catalog.fields(schema), attrs, fn field, params ->
        joins =
          Portable.decode(
            node["blocks"][field.name],
            bindings,
            schema.__schema__(:association, field.association).related,
            actor.id,
            uids
          )
          |> Enum.map(&Brando.Content.Transfer.adapt(&1, bindings))
          |> Enum.with_index(fn block, n -> %{"block" => block, "sequence" => n} end)

        Map.put(params, to_string(field.association), joins)
      end)
    end
  end

  defp resolve!(bindings, token),
    do:
      bindings[token] ||
        Error.fail!(dgettext("content_transfer", "Resolve the entry's referenced content before importing."))

  def gallery_asset?(schema, name),
    do:
      function_exported?(schema, :__naming__, 0) &&
        Enum.any?(Brando.Blueprint.Assets.__assets__(schema), &(&1.name == name && &1.type == :gallery))

  # User-authored JSON keys are not block transport keys. Only rich-text values
  # carry typed link tokens; a custom map's image_id/source_id stays ordinary data.
  defp authored(value, fun, state) when is_map(value) do
    {pairs, state} =
      Enum.map_reduce(value, state, fn {key, value}, state ->
        {value, state} = authored(value, fun, state)
        {{key, value}, state}
      end)

    {Map.new(pairs), state}
  end

  defp authored(value, fun, state) when is_list(value), do: Enum.map_reduce(value, state, &authored(&1, fun, &2))
  defp authored(value, fun, state) when is_binary(value), do: fun.(value, state)
  defp authored(value, _, state), do: {value, state}

  def fingerprint(entry), do: entry |> snapshot() |> Value.digest()

  def records(%Brando.Content.Block{} = block) do
    [
      block
      | Enum.flat_map([:children, :refs, :vars, :table_rows, :block_identifiers], fn name ->
          Enum.flat_map(List.wrap(Map.get(block, name)), &records/1)
        end)
    ]
  end

  def records(%Ecto.Association.NotLoaded{}), do: []

  def records(entry) do
    children =
      Enum.flat_map(owned(entry.__struct__), fn {name, _, _} ->
        Enum.flat_map(List.wrap(Map.get(entry, name)), &records/1)
      end)

    blocks =
      Enum.flat_map(Catalog.fields(entry.__struct__), fn field ->
        Enum.flat_map(Map.get(entry, field.association, []), fn join -> [join | records(join.block)] end)
      end)

    [entry | children ++ blocks]
  end

  defp snapshot(entry) do
    Enum.reduce(owned(entry.__struct__), Params.snapshot(entry), fn {name, _, _}, acc ->
      value =
        case Map.get(entry, name) do
          nil -> nil
          values when is_list(values) -> Enum.map(values, &snapshot/1)
          child -> snapshot(child)
        end

      Map.put(acc, to_string(name), value)
    end)
  end
end
