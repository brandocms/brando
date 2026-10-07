defmodule Brando.Content.Transfer.Contracts do
  use Gettext, backend: Brando.Gettext
  @moduledoc false
  alias Brando.Content.Transfer.Error
  alias Brando.Drafts.Params
  alias Brando.Repo

  @settings ~w(type multi datasource datasource_module datasource_type datasource_query)
  def capture(module) do
    module = Repo.preload(module, [:refs, :vars])
    data = Params.snapshot(module)

    table =
      if module.table_template_id,
        do: Repo.get!(Brando.Content.TableTemplate, module.table_template_id) |> Repo.preload(:vars) |> table()

    data
    |> settings()
    |> Map.merge(%{
      "refs" => Map.new(data["refs"], &{&1["name"], &1["data"]["type"]}),
      "vars" => types(data["vars"]),
      "table" => table
    })
  end

  # An unset `multi` means false, the column's default: a module stored
  # without it (NULL) and the same definition installed elsewhere (false) are
  # one contract. Mirrors Brando.Content.Definition.Model.normalize_module!/1.
  defp settings(data), do: data |> Map.take(@settings) |> unset_multi()
  defp unset_multi(data), do: Map.update(data, "multi", false, &(&1 || false))

  def table(table), do: table |> Params.snapshot() |> Map.fetch!("vars") |> types()
  defp types(vars), do: Map.new(vars, &{&1["key"], &1["type"]})

  def normalized(module) do
    module |> Params.snapshot() |> Map.take(@settings ++ ~w(code class refs vars)) |> unset_multi() |> normalize()
  end

  defp normalize(value) when is_map(value) do
    value
    |> Map.reject(fn {key, _} ->
      key in ~w(id uid version sequence creator_id updated_by_id inserted_at updated_at edited_at content_modified_at) ||
        String.ends_with?(key, "_id")
    end)
    |> Map.new(fn {key, val} -> {key, normalize(val)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value

  def differences(%{"kind" => "module", "definition" => source}, %Brando.Content.Module{} = module) do
    destination = normalized(module)
    for key <- ~w(code class refs vars), source[key] != destination[key], do: key
  end

  def differences(_, _), do: []

  def check!(block, old, module, latest \\ nil) do
    # Bundles exported before the unset-multi rule carry `nil`
    old = unset_multi(old)
    latest = latest || capture(module)
    changed = Enum.filter(@settings, &(old[&1] != latest[&1]))

    if changed != [],
      do:
        Error.fail!(
          dgettext("content_transfer", "Module “%{value1}” has incompatible settings: %{value2}.",
            value1: Brando.Content.Transfer.Dependencies.label(module),
            value2: Enum.join(changed, ", ")
          )
        )

    compare!(old["refs"], latest["refs"], "reference")
    compare!(Map.new(block["refs"], &{&1["name"], &1["data"]["type"]}), latest["refs"], "reference")
    compare!(old["vars"], latest["vars"], "variable")
    compare!(types(block["vars"]), latest["vars"], "variable")

    if old["table"] != latest["table"],
      do:
        Error.fail!(
          dgettext(
            "content_transfer",
            "The destination table columns differ from the source. Reconcile the table template first."
          )
        )

    Enum.each(block["table_rows"], &compare!(types(&1["vars"]), latest["table"] || %{}, "table column"))
    :ok
  end

  defp compare!(old, current, kind) do
    Enum.each(old || %{}, fn {name, type} ->
      # Retained region content survives a removed insertion point.
      unless (kind == "reference" && type == "blocks" && is_nil(current[name])) || compatible?(type, current[name]),
        do:
          Error.fail!(
            dgettext(
              "content_transfer",
              "The destination %{value1} “%{value2}” is missing or has a different type.",
              value1: kind,
              value2: name
            )
          )
    end)
  end

  defp compatible?(same, same), do: true
  defp compatible?(type, "media"), do: type in ~w(picture video gallery svg file)
  defp compatible?(_, _), do: false

  def defaults(params, module) do
    Enum.reduce([{"refs", "name", module.refs}, {"vars", "key", module.vars}], params, fn {field, key, definitions},
                                                                                          acc ->
      existing = acc[field]

      additions =
        definitions
        |> Enum.reject(fn definition ->
          Enum.any?(existing, &(&1[key] == Map.get(definition, String.to_existing_atom(key))))
        end)
        |> Enum.map(&definition_defaults(&1, field))

      Map.put(acc, field, existing ++ additions)
    end)
  end

  defp definition_defaults(definition, field) do
    definition
    |> Params.snapshot()
    |> Map.take(
      if(field == "vars",
        do: Brando.Content.Transfer.Portable.var_fields(),
        else: ~w(name description active collapsed sequence data image_id video_id file_id gallery_id)
      )
    )
    |> then(fn value -> if field == "refs", do: Map.put(value, "uid", Brando.Utils.generate_uid()), else: value end)
  end
end
