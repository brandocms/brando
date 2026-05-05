defmodule Brando.AI.Translation do
  @moduledoc """
  Translates all text content in a duplicated entry using the configured AI provider.

  Collects translatable content from entry fields, block vars, block refs,
  and table row vars, then sends batched prompts to the AI provider and
  applies the translations back to the database.
  """

  require Logger

  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Repo
  alias Brando.Villain.Blocks.GalleryBlock
  alias Brando.Villain.Blocks.HeaderBlock
  alias Brando.Villain.Blocks.HtmlBlock
  alias Brando.Villain.Blocks.MarkdownBlock
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Brando.Villain.Blocks.VideoBlock

  @batch_char_limit 12_000
  @translatable_var_types [:string, :text, :html]

  # PolymorphicEmbed resolves to the wrapper struct (e.g. TextBlock),
  # which contains the actual Data struct at .data (e.g. TextBlock.Data)
  @text_ref_wrapper_types [TextBlock, HtmlBlock, HeaderBlock, MarkdownBlock]

  @doc """
  Translates all text content in an entry from `source_lang` to `target_lang`.

  The entry should already be duplicated (new record). This function fetches
  the entry, collects translatable content, translates via AI, and writes
  the translations back.

  Accepts an optional `progress_fn` callback that receives step atoms.
  """
  def translate_entry(schema, entry_id, source_lang, target_lang, progress_fn \\ &default_progress/1) do
    progress_fn.(:fetching)

    preloads = Brando.Blueprint.preloads_for(schema)

    case Repo.get(schema, entry_id) |> Repo.preload(preloads) do
      nil ->
        {:error, "Entry not found"}

      entry ->
        progress_fn.(:collecting)
        items = collect_translatable_content(entry, schema)

        if items == [] do
          progress_fn.(:complete)
          {:ok, entry_id}
        else
          batches = build_batches(items, source_lang, target_lang)
          total_batches = length(batches)

          translated_items =
            batches
            |> Enum.with_index(1)
            |> Enum.reduce_while([], fn {batch, idx}, acc ->
              progress_fn.({:translating, idx, total_batches})

              case translate_batch(batch, source_lang, target_lang) do
                {:ok, translations} ->
                  {:cont, acc ++ translations}

                {:error, reason} ->
                  {:halt, {:error, reason}}
              end
            end)

          case translated_items do
            {:error, reason} ->
              {:error, reason}

            translations when is_list(translations) ->
              progress_fn.(:applying)
              apply_translations(translations, entry, schema)
              update_slugs(entry, schema)

              progress_fn.(:rendering)

              if schema.has_trait(Brando.Trait.Blocks) do
                case Brando.Content.Blocks.render_entry(schema, entry_id) do
                  {:ok, _} -> :ok
                  {:error, reason} -> Logger.warning("Re-render after translation failed: #{inspect(reason)}")
                end
              end

              progress_fn.(:complete)
              {:ok, entry_id}
          end
        end
    end
  rescue
    e ->
      Logger.error("Translation failed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}")
      {:error, Exception.message(e)}
  end

  defp default_progress(_step), do: :ok

  # --- Content Collection ---

  @doc """
  Collects all translatable content from an entry.

  Returns a list of tagged tuples identifying each piece of text:
  - `{:field, field_name, text}`
  - `{:var, var_id, text}`
  - `{:ref, ref_id, text}`
  - `{:ref_picture, ref_id, field, text}`
  - `{:ref_video, ref_id, :title, text}`
  - `{:ref_gallery, ref_id, override_idx, field, text}`
  - `{:table_var, var_id, text}`
  """
  def collect_translatable_content(entry, schema) do
    field_items = collect_entry_fields(entry, schema)
    block_items = collect_block_content(entry, schema)
    field_items ++ block_items
  end

  @meta_fields [:meta_title, :meta_description]

  @doc """
  Identifies translatable text fields from the blueprint form definition
  and trait-injected fields (e.g. meta fields).

  Walks `schema.__form__().tabs` -> fieldsets -> fields and extracts field
  names where the input type is `:text`, `:textarea`, or `:rich_text`.
  Also includes meta fields if the schema has the Meta trait.
  """
  def translatable_text_fields(schema) do
    form_fields =
      case schema.__form__() do
        %{tabs: tabs} ->
          for tab <- tabs,
              fieldset <- tab.fields,
              field <- fieldset.fields,
              name <- extract_translatable_names(field),
              do: name

        _ ->
          []
      end

    meta_fields =
      if schema.has_trait(Brando.Trait.Meta) do
        @meta_fields
      else
        []
      end

    Enum.uniq(form_fields ++ meta_fields)
  end

  defp extract_translatable_names(%Brando.Blueprint.Forms.Input{type: type, name: name})
       when type in [:text, :textarea, :rich_text],
       do: [name]

  defp extract_translatable_names(%Brando.Blueprint.Forms.Subform{}), do: []

  defp extract_translatable_names(_), do: []

  defp collect_entry_fields(entry, schema) do
    fields = translatable_text_fields(schema)

    Enum.reduce(fields, [], fn field, acc ->
      case Map.get(entry, field) do
        value when is_binary(value) and value != "" ->
          [{:field, field, value} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp collect_block_content(entry, schema) do
    if schema.has_trait(Brando.Trait.Blocks) do
      schema.__blocks_fields__()
      |> Enum.flat_map(fn %{name: assoc_name} ->
        entry_assoc_name = :"entry_#{assoc_name}"

        case Map.get(entry, entry_assoc_name) do
          entry_blocks when is_list(entry_blocks) ->
            Enum.flat_map(entry_blocks, fn entry_block ->
              collect_from_block(entry_block.block)
            end)

          _ ->
            []
        end
      end)
    else
      []
    end
  end

  defp collect_from_block(nil), do: []

  defp collect_from_block(block) do
    var_items = collect_from_vars(block.vars || [])
    ref_items = collect_from_refs(block.refs || [])
    table_items = collect_from_table_rows(block.table_rows || [])
    meta_items = collect_from_identifier_metas(block)

    child_items =
      (block.children || [])
      |> Enum.flat_map(&collect_from_block/1)

    var_items ++ ref_items ++ table_items ++ meta_items ++ child_items
  end

  defp collect_from_vars(vars) do
    Enum.reduce(vars, [], fn var, acc ->
      if var.type in @translatable_var_types and is_binary(var.value) and var.value != "" do
        [{:var, var.id, var.value} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp collect_from_refs(refs) do
    Enum.flat_map(refs, fn ref ->
      # PolymorphicEmbed resolves to wrapper struct (e.g. %TextBlock{data: %TextBlock.Data{text: ...}})
      case ref.data do
        %wrapper{data: inner_data} when wrapper in @text_ref_wrapper_types ->
          text = Map.get(inner_data, :text)

          if is_binary(text) and text != "" do
            [{:ref, ref.id, text}]
          else
            []
          end

        %PictureBlock{data: inner_data} ->
          collect_picture_overrides(ref, inner_data)

        %VideoBlock{data: inner_data} ->
          collect_video_overrides(ref, inner_data)

        %GalleryBlock{data: inner_data} ->
          collect_gallery_overrides(ref, inner_data)

        _ ->
          []
      end
    end)
  end

  defp collect_picture_overrides(ref, data) do
    fields = [:title, :credits, :alt]

    Enum.reduce(fields, [], fn field, acc ->
      # Use override value if set, otherwise fall back to image field
      override_val = Map.get(data, field)

      text =
        if is_binary(override_val) and override_val != "" do
          override_val
        else
          case ref.image do
            %{} = image -> Map.get(image, field)
            _ -> nil
          end
        end

      if is_binary(text) and text != "" do
        [{:ref_picture, ref.id, field, text} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp collect_video_overrides(ref, data) do
    override_val = data.title

    text =
      if is_binary(override_val) and override_val != "" do
        override_val
      else
        case ref.video do
          %{title: title} when is_binary(title) and title != "" -> title
          _ -> nil
        end
      end

    if is_binary(text) and text != "" do
      [{:ref_video, ref.id, :title, text}]
    else
      []
    end
  end

  defp collect_gallery_overrides(ref, data) do
    overrides = data.gallery_object_overrides || []
    gallery_objects = get_gallery_objects(ref)

    overrides
    |> Enum.with_index()
    |> Enum.flat_map(fn {override, idx} ->
      collect_single_gallery_override(ref.id, override, idx, gallery_objects)
    end)
  end

  defp get_gallery_objects(ref) do
    case ref.gallery do
      %{gallery_objects: objects} when is_list(objects) -> objects
      _ -> []
    end
  end

  defp collect_single_gallery_override(ref_id, override, idx, gallery_objects) do
    [:title, :credits, :alt]
    |> Enum.reduce([], fn field, acc ->
      use_default_field = :"use_default_#{field}"
      use_default? = Map.get(override, use_default_field, true)
      override_val = Map.get(override, field)

      text =
        if !use_default? and is_binary(override_val) and override_val != "" do
          override_val
        else
          # Fall back to gallery object's image/video text
          find_gallery_object_text(gallery_objects, override.object_id, field)
        end

      if is_binary(text) and text != "" do
        [{:ref_gallery, ref_id, idx, field, text} | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp find_gallery_object_text(gallery_objects, object_id, field) do
    object_id_str = to_string(object_id)

    case Enum.find(gallery_objects, fn go -> to_string(go.id) == object_id_str end) do
      nil ->
        nil

      gallery_object ->
        cond do
          gallery_object.image -> Map.get(gallery_object.image, field)
          gallery_object.video -> Map.get(gallery_object.video, field)
          true -> nil
        end
    end
  end

  defp collect_from_table_rows(table_rows) do
    Enum.flat_map(table_rows, fn row ->
      Enum.reduce(row.vars || [], [], fn var, acc ->
        if var.type in @translatable_var_types and is_binary(var.value) and var.value != "" do
          [{:table_var, var.id, var.value} | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp collect_from_identifier_metas(%{identifier_metas: metas, id: block_id})
       when is_map(metas) and map_size(metas) > 0 do
    Enum.flat_map(metas, fn {identifier_key, meta_map} ->
      Enum.reduce(meta_map, [], fn {field, value}, acc ->
        if is_binary(value) and value != "" do
          [{:identifier_meta, block_id, identifier_key, field, value} | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp collect_from_identifier_metas(_), do: []

  # --- Prompt Building & Batching ---

  @doc """
  Builds a translation prompt for a list of items.

  Returns the system prompt and numbered user content.
  """
  def build_translation_prompt(items, source_lang, target_lang) do
    source_name = resolve_language_name(source_lang)
    target_name = resolve_language_name(target_lang)

    system_prompt = """
    You are a professional translator. Translate the following numbered text items \
    from #{source_name} to #{target_name}.

    RULES:
    - Preserve ALL HTML tags, attributes, and formatting exactly as they are
    - Only translate the human-readable text content
    - Return your response in the exact same numbered format: "1: translated text"
    - Each numbered item must be on its own line
    - Do not add any preamble, explanation, or extra text
    - Do not skip any items
    - Maintain the same tone and style as the original
    """

    numbered_content =
      items
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{_tag, _id_or_field, text}, idx} ->
        "#{idx}: #{text}"
      end)

    {system_prompt, numbered_content}
  end

  defp resolve_language_name(lang) do
    lang_str = to_string(lang)

    case Enum.find(Brando.config(:languages), fn l -> l[:value] == lang_str end) do
      nil -> String.upcase(lang_str)
      config -> config[:text] || String.upcase(lang_str)
    end
  end

  defp build_batches(items, _source_lang, _target_lang) do
    # Flatten items to just text for size calculation, keeping tags
    items
    |> Enum.reduce({[], [], 0}, fn item, {batches, current_batch, current_size} ->
      {_tag, _id, text} = normalize_item_for_size(item)
      item_size = String.length(text)

      if current_size + item_size > @batch_char_limit and current_batch != [] do
        {[Enum.reverse(current_batch) | batches], [item], item_size}
      else
        {batches, [item | current_batch], current_size + item_size}
      end
    end)
    |> then(fn {batches, current_batch, _} ->
      if current_batch != [] do
        Enum.reverse([Enum.reverse(current_batch) | batches])
      else
        Enum.reverse(batches)
      end
    end)
  end

  # Normalize different tuple arities for size calculation
  defp normalize_item_for_size({_tag, _id, text}) when is_binary(text), do: {nil, nil, text}
  defp normalize_item_for_size({_tag, _id, _field, text}) when is_binary(text), do: {nil, nil, text}
  defp normalize_item_for_size({_tag, _id, _idx, _field, text}) when is_binary(text), do: {nil, nil, text}

  defp translate_batch(items, source_lang, target_lang) do
    # Build a simplified list for the prompt (3-tuples with just text)
    prompt_items = Enum.map(items, &simplify_for_prompt/1)
    {system_prompt, numbered_content} = build_translation_prompt(prompt_items, source_lang, target_lang)

    prompt = "#{numbered_content}"

    case Brando.AI.generate_text(prompt, system_prompt: system_prompt, max_tokens: 16_000) do
      {:ok, %{text: response_text}} ->
        translations = parse_translation_response(response_text, length(items))

        result =
          items
          |> Enum.zip(translations)
          |> Enum.map(fn {item, translated_text} ->
            put_translated_text(item, translated_text)
          end)

        {:ok, result}

      {:error, reason} ->
        {:error, "AI translation failed: #{inspect(reason)}"}
    end
  end

  # Convert any item to a 3-tuple for the prompt builder
  defp simplify_for_prompt({tag, id, text}) when is_binary(text), do: {tag, id, text}
  defp simplify_for_prompt({_tag, _id, _field, text}), do: {:simplified, nil, text}
  defp simplify_for_prompt({_tag, _id, _idx, _field, text}), do: {:simplified, nil, text}

  # Put translated text back into the original tagged tuple
  defp put_translated_text({tag, id, _text}, translated), do: {tag, id, translated}
  defp put_translated_text({tag, id, field, _text}, translated), do: {tag, id, field, translated}
  defp put_translated_text({tag, id, idx, field, _text}, translated), do: {tag, id, idx, field, translated}

  @doc """
  Parses a numbered translation response back to a list of strings.

  Handles edge cases like whitespace, missing numbers, and LLM preamble.
  """
  def parse_translation_response(response, expected_count) do
    lines =
      response
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Try to parse numbered lines
    parsed =
      Enum.reduce(lines, %{}, fn line, acc ->
        case Regex.run(~r/^(\d+)\s*[:.]\s*(.+)$/s, line) do
          [_, num_str, text] ->
            num = String.to_integer(num_str)
            Map.put(acc, num, String.trim(text))

          _ ->
            acc
        end
      end)

    # Build ordered result list
    Enum.map(1..expected_count//1, fn i ->
      Map.get(parsed, i, "")
    end)
  end

  # --- Apply Translations ---

  @doc """
  Applies translated content back to the database.
  """
  def apply_translations(translations, entry, schema) do
    Enum.each(translations, fn item ->
      apply_single_translation(item, entry, schema)
    end)
  end

  defp update_slugs(entry, schema) do
    slug_fields = schema.__slug_fields__()

    if slug_fields != [] do
      # Re-read entry to get translated field values
      fresh_entry = Repo.get(schema, entry.id)

      changes =
        Enum.reduce(slug_fields, %{}, fn slug_field, acc ->
          # Get the source field from the form input opts
          source = get_slug_source(schema, slug_field.name)

          slug_value =
            case source do
              nil ->
                nil

              fields when is_list(fields) ->
                fields
                |> Enum.map_join("-", &to_string(Map.get(fresh_entry, &1, "")))
                |> Brando.Utils.slugify()

              field when is_atom(field) ->
                fresh_entry |> Map.get(field, "") |> to_string() |> Brando.Utils.slugify()
            end

          if slug_value && slug_value != "" do
            Map.put(acc, slug_field.name, slug_value)
          else
            acc
          end
        end)

      if changes != %{} do
        fresh_entry
        |> Ecto.Changeset.change(changes)
        |> Repo.update()
      end
    end
  end

  defp get_slug_source(schema, slug_field_name) do
    case schema.__form__() do
      %{tabs: tabs} ->
        Enum.find_value(tabs, fn tab ->
          Enum.find_value(tab.fields, fn fieldset ->
            Enum.find_value(fieldset.fields, fn
              %Brando.Blueprint.Forms.Input{name: ^slug_field_name, type: :slug, opts: opts} ->
                Keyword.get(opts, :source)

              _ ->
                nil
            end)
          end)
        end)

      _ ->
        nil
    end
  end

  defp apply_single_translation({:field, field_name, translated_text}, entry, _schema) do
    entry
    |> Ecto.Changeset.change(%{field_name => translated_text})
    |> Repo.update()
  end

  defp apply_single_translation({:var, var_id, translated_text}, _entry, _schema) do
    case Repo.get(Var, var_id) do
      nil -> :ok
      var -> var |> Ecto.Changeset.change(%{value: translated_text}) |> Repo.update()
    end
  end

  defp apply_single_translation({:ref, ref_id, translated_text}, _entry, _schema) do
    update_ref_inner_data(ref_id, fn inner -> Map.put(inner, :text, translated_text) end)
  end

  defp apply_single_translation({:ref_picture, ref_id, field, translated_text}, _entry, _schema) do
    update_ref_inner_data(ref_id, fn inner -> Map.put(inner, field, translated_text) end)
  end

  defp apply_single_translation({:ref_video, ref_id, :title, translated_text}, _entry, _schema) do
    update_ref_inner_data(ref_id, fn inner -> Map.put(inner, :title, translated_text) end)
  end

  defp apply_single_translation({:ref_gallery, ref_id, override_idx, field, translated_text}, _entry, _schema) do
    update_ref_inner_data(ref_id, fn inner ->
      overrides = inner.gallery_object_overrides || []

      updated_overrides =
        List.update_at(overrides, override_idx, fn override ->
          use_default_field = :"use_default_#{field}"

          override
          |> Map.put(field, translated_text)
          |> Map.put(use_default_field, false)
        end)

      Map.put(inner, :gallery_object_overrides, updated_overrides)
    end)
  end

  defp apply_single_translation({:table_var, var_id, translated_text}, _entry, _schema) do
    case Repo.get(Var, var_id) do
      nil -> :ok
      var -> var |> Ecto.Changeset.change(%{value: translated_text}) |> Repo.update()
    end
  end

  defp apply_single_translation({:identifier_meta, block_id, identifier_key, field, translated_text}, _entry, _schema) do
    case Repo.get(Brando.Content.Block, block_id) do
      nil ->
        :ok

      block ->
        updated_metas = put_in(block.identifier_metas, [identifier_key, field], translated_text)

        block
        |> Ecto.Changeset.change(%{identifier_metas: updated_metas})
        |> Repo.update()
    end
  end

  # Updates the inner `.data` of a ref's wrapper struct.
  # ref.data is a wrapper (e.g. %TextBlock{data: %TextBlock.Data{...}})
  # update_fn receives the inner Data struct, returns the updated inner Data struct
  defp update_ref_inner_data(ref_id, update_fn) do
    case Repo.get(Ref, ref_id) do
      nil ->
        :ok

      ref ->
        ref = Repo.preload(ref, Ref.preloads())
        wrapper = ref.data
        inner_data = wrapper.data
        updated_inner = update_fn.(inner_data)
        updated_wrapper = %{wrapper | data: updated_inner}

        # PolymorphicEmbed fields are excluded from Blueprint's castable_fields,
        # so we must build the changeset manually with cast + cast_polymorphic_embed
        data_params = poly_embed_to_params(updated_wrapper)

        ref
        |> Ecto.Changeset.cast(%{"data" => data_params}, [])
        |> PolymorphicEmbed.cast_polymorphic_embed(:data)
        |> Repo.update()
    end
  end

  defp poly_embed_to_params(struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> stringify_keys()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_value(%_{} = struct) do
    struct |> Map.from_struct() |> stringify_keys()
  end

  defp stringify_value(list) when is_list(list) do
    Enum.map(list, &stringify_value/1)
  end

  defp stringify_value(value), do: value
end
