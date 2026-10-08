defmodule Brando.Search.Text do
  @moduledoc """
  Plain text for the search index (`Brando.Search`), from an entry's text
  fields and its blocks.

  Blocks are read recursively, in order: text and rich text, headings,
  Markdown and HTML refs (without their tags), lists and table cells, picture
  alt text, titles and credits, gallery captions, video and file titles,
  container and multi-module children, and the text, rich-text and link
  variables of modules and table rows. Inactive blocks and refs, which do
  not render, are left out, and so are code, maps and embeds.

  Text is cut at `max_bytes/0` (about 200 KB) per document, on a character
  boundary.
  """

  alias Brando.Type.I18nString
  alias Brando.Villain.Blocks

  @max_bytes 200_000
  @text_inputs [:text, :textarea, :rich_text]
  @text_vars [:string, :text, :html]

  @doc "The most text a document holds, in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc """
  The entry's body: its text fields, then the text of its blocks, one piece
  per line, cut at `max_bytes/0`. `fields` are the text fields to read (see
  `text_fields/1`); `language` picks the text of translated media captions.
  """
  @spec body(struct(), [atom()], String.t() | nil) :: String.t()
  def body(entry, fields, language) do
    field_text = Enum.flat_map(fields, &field(entry, &1))

    block_text =
      entry.__struct__
      |> block_fields()
      |> Enum.flat_map(fn name -> blocks(Map.get(entry, :"entry_#{name}"), language) end)

    (field_text ++ block_text)
    |> Enum.join("\n")
    |> cap()
  end

  defp field(entry, name) do
    case Map.get(entry, name) do
      value when is_binary(value) -> present(plain(value))
      _ -> []
    end
  end

  defp block_fields(schema) do
    if function_exported?(schema, :__blocks_fields__, 0),
      do: Enum.map(schema.__blocks_fields__(), & &1.name),
      else: []
  end

  @doc """
  The schema's text fields: the attributes its forms edit as text, text
  areas or rich text, other than the title and slugs, which are indexed on
  their own. A schema without forms has its `:text` attributes.
  """
  @spec text_fields(module()) :: [atom()]
  def text_fields(schema) do
    attributes = Map.new(Brando.Blueprint.Attributes.__attributes__(schema), &{&1.name, &1.type})
    skip = [:title, :meta_title, :meta_description | Enum.map(schema.__slug_fields__(), & &1.name)]

    candidates =
      case form_inputs(schema) do
        [] -> for {name, :text} <- attributes, do: name
        inputs -> for %{name: name, type: type} <- inputs, type in @text_inputs, do: name
      end

    candidates
    |> Enum.filter(&(Map.get(attributes, &1) in [:string, :text]))
    |> Enum.reject(&(&1 in skip))
    |> Enum.uniq()
  end

  defp form_inputs(schema) do
    if function_exported?(schema, :__forms__, 0) do
      schema.__forms__()
      |> Enum.flat_map(& &1.tabs)
      |> Enum.flat_map(& &1.fields)
      |> Enum.flat_map(&inputs/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp inputs(%Brando.Blueprint.Forms.Input{} = input), do: [input]
  defp inputs(%Brando.Blueprint.Forms.Fieldset{fields: fields}), do: Enum.flat_map(fields, &inputs/1)
  defp inputs(_), do: []

  @doc """
  The text of a list of blocks, or of entry blocks (the join records of a
  block field), one piece per line.
  """
  @spec blocks([struct()] | nil, String.t() | nil) :: [String.t()]
  def blocks(blocks, language \\ nil)

  def blocks(blocks, language) when is_list(blocks) do
    blocks
    |> Enum.map(&unwrap/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&(Map.get(&1, :sequence) || 0))
    |> Enum.flat_map(&block(&1, language))
  end

  def blocks(_blocks, _language), do: []

  # An entry block (`Page.Block`) holds its block
  defp unwrap(%{block: %{} = block} = entry_block) when not is_struct(entry_block, Brando.Content.Block),
    do: Map.put_new(block, :sequence, Map.get(entry_block, :sequence))

  defp unwrap(%{block: _}), do: nil
  defp unwrap(block), do: block

  defp block(%{active: false}, _language), do: []
  defp block(%{marked_as_deleted: true}, _language), do: []

  defp block(block, language) do
    Enum.flat_map(by_sequence(Map.get(block, :refs)), &ref(&1, language)) ++
      Enum.flat_map(by_sequence(Map.get(block, :vars)), &var/1) ++
      Enum.flat_map(by_sequence(Map.get(block, :table_rows)), &table_row/1) ++
      blocks(loaded(Map.get(block, :children)), language)
  end

  defp table_row(row), do: Enum.flat_map(by_sequence(Map.get(row, :vars)), &var/1)

  defp var(%{type: type, value: value}) when type in @text_vars and is_binary(value), do: present(plain(value))
  defp var(%{type: :link, link_text: text}) when is_binary(text), do: present(plain(text))
  defp var(_), do: []

  @doc "The text of one ref, by the kind of block it holds."
  @spec ref(struct(), String.t() | nil) :: [String.t()]
  def ref(%{active: false}, _language), do: []

  def ref(%{data: %module{data: data}} = ref, language) when is_map(data) do
    ref_text(module, data, ref, language)
  end

  def ref(_ref, _language), do: []

  defp ref_text(module, data, _ref, _language)
       when module in [Blocks.TextBlock, Blocks.HeaderBlock, Blocks.MarkdownBlock, Blocks.HtmlBlock],
       do: present(plain(data.text))

  defp ref_text(Blocks.PictureBlock, data, ref, language) do
    image = loaded(Map.get(ref, :image))

    [
      override(data, :title, image, language),
      override(data, :alt, image, language),
      override(data, :credits, image, language)
    ]
    |> Enum.flat_map(&present/1)
  end

  defp ref_text(Blocks.GalleryBlock, data, ref, language) do
    overrides = Map.get(data, :gallery_object_overrides) || []

    case loaded(Map.get(ref, :gallery)) do
      %{gallery_objects: objects} when is_list(objects) ->
        objects
        |> Enum.sort_by(&(Map.get(&1, :sequence) || 0))
        |> Enum.flat_map(&gallery_object(&1, overrides, language))

      _ ->
        Enum.flat_map(overrides, fn override ->
          Enum.flat_map([:title, :caption, :alt, :credits], &present(Map.get(override, &1)))
        end)
    end
  end

  defp ref_text(Blocks.VideoBlock, data, _ref, _language), do: present(data.title)

  defp ref_text(Blocks.FileBlock, data, _ref, _language),
    do: Enum.flat_map([data.title, data.label, data.description], &present/1)

  defp ref_text(_module, _data, _ref, _language), do: []

  # A picture ref's own text replaces the image's
  defp override(data, key, image, language) do
    case Map.get(data, key) do
      value when is_binary(value) and value != "" -> value
      _ -> image && I18nString.get(Map.get(image, key), language)
    end
  end

  defp gallery_object(object, overrides, language) do
    media = loaded(Map.get(object, :image)) || loaded(Map.get(object, :video))
    media_id = media && to_string(media.id)
    override = Enum.find(overrides, &(to_string(Map.get(&1, :object_id)) == media_id)) || %{}

    Enum.flat_map([:title, :caption, :alt, :credits], fn key ->
      value =
        if Map.get(override, :"use_default_#{key}") == false,
          do: Map.get(override, key),
          else: media && I18nString.get(Map.get(media, key), language)

      present(value && plain(value))
    end)
  end

  defp by_sequence(list) when is_list(list), do: Enum.sort_by(list, &(Map.get(&1, :sequence) || 0))
  defp by_sequence(_), do: []

  defp loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded(value), do: value

  @doc """
  A title as text: entities decoded (a HEEx identifier escapes it), control
  characters gone and whitespace collapsed. Anything that looks like a tag
  is kept as the text it is.
  """
  @spec title(String.t() | nil) :: String.t()
  def title(nil), do: ""

  def title(text) when is_binary(text) do
    text
    |> HtmlEntities.decode()
    |> String.replace(~r/[\x00-\x1F\x7F]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc """
  Plain text from HTML or text: tags removed (block elements end a line),
  entities decoded, control characters gone and whitespace collapsed.
  """
  @spec plain(String.t() | nil) :: String.t()
  def plain(nil), do: ""

  def plain(text) when is_binary(text) do
    text
    |> strip_tags()
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, "")
    |> String.replace(~r/[ \t\r\f\v\x{00A0}]+/u, " ")
    |> String.replace(~r/\s*\n\s*/u, "\n")
    |> String.trim()
  end

  defp strip_tags(text) do
    if String.contains?(text, ["<", "&"]) do
      text
      |> Floki.parse_fragment!()
      |> Floki.traverse_and_update(fn
        {tag, attrs, children} when tag in ~w(p div li h1 h2 h3 h4 h5 h6 blockquote pre tr br td th) ->
          {tag, attrs, children ++ ["\n"]}

        node ->
          node
      end)
      |> Floki.text(style: false)
    else
      text
    end
  rescue
    _ -> text
  end

  @doc "Cuts `text` to at most `max_bytes/0` bytes, on a character boundary."
  @spec cap(String.t(), pos_integer()) :: String.t()
  def cap(text, bytes \\ @max_bytes)
  def cap(text, bytes) when byte_size(text) <= bytes, do: text

  def cap(text, bytes) do
    text
    |> binary_part(0, bytes)
    |> valid_prefix()
  end

  # Drops a character cut in two at the end
  defp valid_prefix(binary) do
    if String.valid?(binary), do: binary, else: valid_prefix(binary_part(binary, 0, byte_size(binary) - 1))
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp present(_), do: []
end
