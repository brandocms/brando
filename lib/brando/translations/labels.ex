defmodule Brando.Translations.Labels do
  @moduledoc """
  Names a synchronized translation's work items as the entry form's work list
  shows them: a field by its form label, a block by its module's name and
  the ref or variable in it (`"Text › Body"`), a subform row's field by the
  subform's and the field's labels.

  Shared by the form (`BrandoAdmin.Components.Form.Translation`) and
  `Brando.Translations.Work`, so a model reading the work over MCP sees the
  same names as the editor.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.Translations.Sync

  @typedoc """
  Where a work item's path points: a field, a block (by its `uid` in the
  translation, with its module's name and the rest of the path) or a
  subform row's field.
  """
  @type target ::
          {:field, String.t()}
          | {:block, String.t(), String.t(), [String.t()]}
          | {:row, String.t(), String.t(), String.t()}

  @doc """
  The blocks of `payload` at any depth, by the identity work item paths use
  (`Brando.Translations.Sync.block_identities/1`): each block's `uid`, module name, variables, the
  identifier ids it links to, and the block itself.
  """
  def block_index(schema, payload) do
    fields =
      if Code.ensure_loaded?(schema) and function_exported?(schema, :__blocks_fields__, 0),
        do: Enum.map(schema.__blocks_fields__(), &:"entry_#{&1.name}"),
        else: []

    fields
    |> Enum.flat_map(fn field ->
      case Map.get(payload, field) do
        joins when is_list(joins) ->
          blocks = Enum.map(joins, & &1.block)
          identities = Sync.block_identities(blocks)
          blocks |> Enum.flat_map(&walk/1) |> Enum.map(&{identities[&1.uid], &1})

        _ ->
          []
      end
    end)
    |> Map.new(fn {identity, block} ->
      vars = if is_list(block.vars), do: block.vars, else: []
      links = if is_list(block.block_identifiers), do: Enum.map(block.block_identifiers, & &1.identifier_id), else: []
      {identity, %{uid: block.uid, module_name: module_name(block), vars: vars, identifier_ids: links, block: block}}
    end)
  end

  defp walk(nil), do: []

  defp walk(block) do
    children = if is_list(block.children), do: block.children, else: []
    [block | Enum.flat_map(children, &walk/1)]
  end

  @doc "Where a work item's `path` points in the form, given `block_index/2`."
  @spec target(String.t(), map()) :: target()
  def target(path, blocks) do
    case String.split(path, "/") do
      ["entry_" <> _field, identity | rest] ->
        case blocks[identity] do
          nil -> {:field, path}
          block -> {:block, block.uid, block.module_name, rest}
        end

      [field] ->
        {:field, field}

      # A tree relation waiting for an entry's translation: `parent/12`
      [field, id] ->
        if id =~ ~r/^\d+$/, do: {:field, field}, else: {:field, path}

      [subform, uid, field] ->
        {:row, subform, uid, field}

      _ ->
        {:field, path}
    end
  end

  @doc "The label of a `target/2`, with the form's `field_labels/1`."
  @spec label(target(), map()) :: String.t()
  def label({:block, _uid, module_name, rest}, _labels), do: Enum.join([module_name | block_part(rest)], " › ")

  def label({:row, subform, _uid, field}, labels),
    do: "#{labels[subform] || humanize(subform)} › #{labels[subform <> "/" <> field] || humanize(field)}"

  def label({:field, field}, labels), do: labels[field] || labels[field <> "_id"] || humanize(field)

  defp block_part(["refs", name, "text"]), do: [humanize(name)]
  defp block_part(["refs", name, "media"]), do: [humanize(name), gettext("media")]
  defp block_part(["refs", name, "gallery" | _]), do: [humanize(name), gettext("gallery")]
  # An HTML ref's `text` parameter
  defp block_part(["refs", name, "values", key]), do: [humanize(name), humanize(key)]
  defp block_part(["refs", name, field]), do: [humanize(name), humanize(field)]
  defp block_part(["vars", key, "media"]), do: [humanize(key), gettext("media")]
  defp block_part(["vars", key, "url"]), do: [humanize(key), "URL"]
  defp block_part(["vars", key | _]), do: [humanize(key)]
  defp block_part(["rows", _row, "vars", key | _]), do: [gettext("Table"), humanize(key)]
  defp block_part(["identifiers" | _]), do: [gettext("Related entries")]
  defp block_part(["identifier_metas" | _]), do: [gettext("Related entries")]
  defp block_part(_rest), do: []

  # A block the pending version added has no module preloaded; its name is
  # looked up by id.
  defp module_name(%{module: %{name: name}}), do: localized(name)

  defp module_name(%{module_id: id} = block) when is_integer(id) do
    case Brando.Content.fetch_module(id, block.module_origin || :local) do
      %{name: name} -> localized(name)
      _ -> gettext("Block")
    end
  end

  defp module_name(_block), do: gettext("Block")

  defp localized(name) when is_map(name),
    do: name[Gettext.get_locale(Brando.Gettext)] || name["en"] || name |> Map.values() |> List.first()

  defp localized(name) when is_binary(name), do: name
  defp localized(_name), do: gettext("Block")

  @doc """
  The labels of `schema`'s default form, by field name, translated in the
  schema's domain as the inputs show them; a subform's fields are listed under
  their subform, as `"subform/field"`.
  """
  def field_labels(schema) do
    naming = schema.__naming__()
    domain = String.downcase("#{naming.domain}_#{naming.schema}")
    gettext_module = schema.__modules__().gettext

    case schema.__form__() do
      %{tabs: tabs} ->
        for tab <- tabs, fieldset <- tab.fields, input <- fieldset.fields, reduce: %{} do
          acc ->
            acc
            |> put_label(input, "", gettext_module, domain)
            |> put_sub_labels(input, gettext_module, domain)
        end

      _ ->
        %{}
    end
  end

  defp put_label(acc, %{name: name} = input, prefix, gettext_module, domain) do
    text = Map.get(input, :label) || (Map.get(input, :opts) || [])[:label]

    if is_binary(text),
      do: Map.put(acc, prefix <> to_string(name), Gettext.dgettext(gettext_module, domain, text)),
      else: acc
  end

  defp put_label(acc, _input, _prefix, _gettext_module, _domain), do: acc

  defp put_sub_labels(acc, %Brando.Blueprint.Forms.Subform{name: name, sub_fields: fields}, gettext_module, domain),
    do: Enum.reduce(fields, acc, &put_label(&2, &1, "#{name}/", gettext_module, domain))

  defp put_sub_labels(acc, _input, _gettext_module, _domain), do: acc

  defp humanize(name), do: name |> to_string() |> Phoenix.Naming.humanize()
end
