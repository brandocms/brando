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

  @owners [:page_id, :global_set_id, :menu_item_id, :table_template_id, :table_row_id]

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
    field = Enum.find(@owners, &Map.get(var, &1))

    dgettext("doctor", "%{owner} %{id}: var %{key}: %{value}",
      owner: owner(field),
      id: if(field, do: Map.get(var, field), else: var.id),
      key: var.key,
      value: value(var.value)
    )
  end

  defp owner(:page_id), do: dgettext("doctor", "Page")
  defp owner(:global_set_id), do: dgettext("doctor", "Global set")
  defp owner(:menu_item_id), do: dgettext("doctor", "Menu item")
  defp owner(:table_template_id), do: dgettext("doctor", "Table template")
  defp owner(:table_row_id), do: dgettext("doctor", "Table row")
  defp owner(nil), do: dgettext("doctor", "Var")

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
    key =
      if Palette.css_name?(palette.key),
        do: [],
        else: [dgettext("doctor", "key %{value} is not a CSS name", value: value(palette.key))]

    namespace =
      if Palette.css_name?(palette.namespace),
        do: [],
        else: [dgettext("doctor", "namespace %{value} is not a CSS name", value: value(palette.namespace))]

    names = key ++ namespace

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
    embeds = for {name, _} <- relations, name in module.__schema__(:embeds), do: name
    # A belongs_to subform's row is preloaded by its foreign key
    foreign_keys =
      for {name, _} <- relations,
          %Ecto.Association.BelongsTo{owner_key: key} <- [module.__schema__(:association, name)],
          do: key

    from(q in module, select: struct(q, ^Enum.uniq([:id | fields ++ embeds ++ foreign_keys])), order_by: q.id)
    |> Repo.all()
    |> Repo.preload(preloads(module, relations))
    |> Enum.flat_map(fn record ->
      {_, cleared} = Color.clear_invalid(record)
      Enum.map(cleared, &"#{inspect(module)} #{record.id}: #{&1}")
    end)
  end

  # A subform's rows, and the rows of its own subforms
  @doc false
  def preloads(module, spec) do
    for {relation, fields} <- spec, %{related: related} <- [module.__schema__(:association, relation)] do
      {relation, preloads(related, fields)}
    end
  end

  defp module_name(nil), do: "-"
  defp module_name(%{name: name}) when is_map(name), do: Brando.Type.I18nString.get(name, nil) || "-"
  defp module_name(%{name: name}), do: to_string(name)

  defp value(value) when is_binary(value) and byte_size(value) > 60, do: inspect(String.slice(value, 0, 60) <> "…")
  defp value(value), do: inspect(value)
end
