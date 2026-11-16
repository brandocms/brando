defmodule Brando.Doctor.Checks.ImageSrcsets do
  @moduledoc """
  Image and gallery fields whose `srcset` names a size their config does not
  have with the `default_config` in effect: a field that declares a `srcset`
  but no `sizes` of its own takes its sizes from `default_config`, which may
  have been narrowed since (in `config/runtime.exs`, say). Such a field is
  read without those entries, and its srcset renders without them
  (`Brando.Blueprint.AssetConfigNormalizer.missing_srcset_sizes/1`).
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Blueprint
  alias Brando.Blueprint.AssetConfigNormalizer
  alias Spark.Dsl.Extension

  @impl true
  def id, do: "image_srcsets"

  @impl true
  def label, do: dgettext("doctor", "Image srcset sizes")

  @impl true
  def run(_context) do
    (Blueprint.list_blueprints() ++ Blueprint.brando_blueprints())
    |> Enum.uniq()
    |> missing_sizes()
    |> evaluate()
  end

  @doc """
  `[{blueprint, field, sizes}]`: each asset field of `blueprints` whose
  `srcset` names `sizes` its config does not have now.
  """
  @spec missing_sizes([module()]) :: [{module(), atom(), [String.t()]}]
  def missing_sizes(blueprints) do
    for blueprint <- blueprints,
        asset <- Extension.get_entities(blueprint, [:assets]),
        sizes = AssetConfigNormalizer.missing_srcset_sizes(asset),
        sizes != [],
        do: {blueprint, asset.name, sizes}
  end

  @doc "Turns `missing_sizes/1` into a result."
  def evaluate([]), do: ok(dgettext("doctor", "every srcset names sizes its field has"))

  def evaluate(fields) do
    warning(
      dngettext(
        "doctor",
        "%{count} field's srcset names sizes default_config no longer gives it",
        "%{count} fields' srcsets name sizes default_config no longer gives them",
        length(fields)
      ),
      fix:
        dgettext(
          "doctor",
          "add each size to default_config, or to the field's own sizes; until then its srcset is rendered without it"
        ),
      items:
        Enum.map(fields, fn {blueprint, name, sizes} -> "#{inspect(blueprint)}.#{name}: #{Enum.join(sizes, ", ")}" end)
    )
  end
end
