defmodule Brando.LivePreview.ValidateTargets do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    duplicate =
      dsl_state
      |> Transformer.get_entities([:live_preview])
      |> Enum.frequencies_by(&{&1.schema, &1.name})
      |> Enum.find(fn {_key, count} -> count > 1 end)

    case duplicate do
      nil ->
        {:ok, dsl_state}

      {{schema, name}, _count} ->
        {:error,
         Spark.Error.DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           path: [:live_preview, :preview_target],
           message: "Duplicate preview target #{inspect(name)} for #{inspect(schema)}. Set a unique name for each view."
         )}
    end
  end
end
