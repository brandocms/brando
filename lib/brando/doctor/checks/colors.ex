defmodule Brando.Doctor.Checks.Colors do
  @moduledoc """
  Stored colours that are not colours (`Brando.Color`), from before colour
  values were checked: module var defaults, colour vars in blocks and
  entries, palette colours, and the `:color` fields of Blueprints (subform
  rows included). Palette keys and namespaces that are not CSS names are
  listed with them.

  They keep working where they are stored, but the site leaves a palette's
  invalid colours out, a new block starts an invalid module default empty, a
  restored revision brings one back empty, and an edit that changes one must
  make it a colour. Fixing them before the upgrade avoids all of that.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Color
  alias Brando.Content.Palette
  alias Brando.Content.Var
  alias Brando.Doctor.Context
  alias Brando.Repo

  @owners [
    page_id: "Page",
    global_set_id: "Global set",
    menu_item_id: "Menu item",
    table_template_id: "Table template",
    table_row_id: "Table row"
  ]

  @impl true
  def id, do: "colors"

  @impl true
  def label, do: dgettext("doctor", "Stored colours")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&find/0)
    |> evaluate()
  end

  @doc "The stored colours that are not colours, and palette names that are not CSS names, as items."
  @spec find() :: [String.t()]
  def find, do: vars() ++ palettes() ++ blueprint_fields()

  @doc "Turns `[{environment_label, [item]}]` into a result."
  def evaluate(per_environment) do
    case for({label, items} <- per_environment, item <- items, do: Context.label_item(label, item)) do
      [] ->
        ok(dgettext("doctor", "every stored colour is a colour"))

      items ->
        warning(
          dngettext(
            "doctor",
            "%{count} stored colour is not a colour",
            "%{count} stored colours are not colours",
            length(items)
          ),
          fix:
            dgettext(
              "doctor",
              "pick each one again in the admin, or set it to a colour such as #1a2b3c, before upgrading: until then the site leaves palette colours out, new blocks start module defaults empty and restored revisions bring them back empty; palette keys take letters, digits, - and _"
            ),
          items: items
        )
    end
  end

  defp vars do
    query =
      from v in Var,
        left_join: m in assoc(v, :module),
        left_join: b in assoc(v, :block),
        left_join: bm in assoc(b, :module),
        where: v.type == :color and not is_nil(v.value) and v.value != "",
        order_by: [v.module_id, bm.id, v.id],
        select: {v, m, bm}

    query
    |> Repo.all()
    |> Enum.reject(fn {var, _module, _block_module} -> Color.valid?(var.value) end)
    |> Enum.group_by(fn {var, module, block_module} -> var_group(var, module, block_module) end)
    |> Enum.flat_map(fn
      {{:blocks, name, uid, key}, vars} ->
        [
          dngettext(
            "doctor",
            "Blocks of module %{module} (%{uid}): var %{key} in %{count} block",
            "Blocks of module %{module} (%{uid}): var %{key} in %{count} blocks",
            length(vars),
            module: name,
            uid: uid,
            key: key
          )
        ]

      {_group, vars} ->
        Enum.map(vars, fn {var, module, _} -> var_item(var, module) end)
    end)
    |> Enum.sort()
  end

  defp var_group(%{block_id: id} = var, _module, block_module) when not is_nil(id),
    do: {:blocks, module_name(block_module), block_module && block_module.uid, var.key}

  defp var_group(var, _module, _block_module), do: {:var, var.id}

  defp var_item(%{module_id: id} = var, module) when not is_nil(id),
    do:
      dgettext("doctor", "Module %{module} (%{uid}): default of var %{key}: %{value}",
        module: module_name(module),
        uid: module && module.uid,
        key: var.key,
        value: value(var.value)
      )

  defp var_item(var, _module) do
    {field, owner} = Enum.find(@owners, {nil, "Var"}, fn {field, _} -> Map.get(var, field) end)

    "#{owner} #{field && Map.get(var, field)}: var #{var.key}: #{value(var.value)}"
  end

  defp palettes do
    for palette <- Repo.all(from(p in Palette, order_by: [p.namespace, p.key])),
        item <- palette_items(palette),
        do:
          dgettext("doctor", "Palette [%{namespace}] %{name}: %{item}",
            namespace: palette.namespace,
            name: palette.name,
            item: item
          )
  end

  defp palette_items(palette) do
    names =
      for {field, name} <- [key: palette.key, namespace: palette.namespace],
          not Palette.css_name?(name),
          do: dgettext("doctor", "%{field} %{value} is not a CSS name", field: field, value: value(name))

    colors =
      for color <- palette.colors || [], item <- color_items(color), do: item

    names ++ colors
  end

  defp color_items(color) do
    key =
      if Palette.css_name?(color.key),
        do: [],
        else: [dgettext("doctor", "colour key %{value} is not a CSS name", value: value(color.key))]

    hex =
      if Color.valid?(color.hex_value),
        do: [],
        else: [dgettext("doctor", "colour %{key}: %{value}", key: color.key, value: value(color.hex_value))]

    key ++ hex
  end

  # The application's Blueprints, and Brando's own besides palettes (above)
  defp blueprint_fields do
    [Brando.Images.Image | Brando.Blueprint.list_blueprints()]
    |> Enum.uniq()
    |> Enum.reject(&(&1 == Palette))
    |> Enum.filter(&stored_colors?/1)
    |> Enum.flat_map(&blueprint_items/1)
  end

  defp stored_colors?(module) do
    function_exported?(module, :__color_fields__, 0) and module.__color_fields__() != [] and
      is_binary(module.__schema__(:source))
  end

  defp blueprint_items(module) do
    spec = module.__color_fields__()
    {fields, relations} = Enum.split_with(spec, &is_atom/1)
    relation_names = Enum.map(relations, &elem(&1, 0))
    {embeds, assocs} = Enum.split_with(relation_names, &(&1 in module.__schema__(:embeds)))

    from(q in module, select: struct(q, ^Enum.uniq([:id | fields ++ embeds])), order_by: q.id)
    |> Repo.all()
    |> Repo.preload(assocs)
    |> Enum.flat_map(fn record ->
      {_, cleared} = Color.clear_invalid(record)
      Enum.map(cleared, &"#{inspect(module)} #{record.id}: #{&1}")
    end)
  end

  defp module_name(nil), do: "-"
  defp module_name(%{name: name}) when is_map(name), do: Brando.Type.I18nString.get(name, nil) || "-"
  defp module_name(%{name: name}), do: to_string(name)

  defp value(value) when is_binary(value) and byte_size(value) > 60, do: inspect(String.slice(value, 0, 60) <> "…")
  defp value(value), do: inspect(value)
end
