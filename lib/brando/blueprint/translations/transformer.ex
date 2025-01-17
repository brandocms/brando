defmodule Brando.Blueprint.Translations.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def before?(_) do
    false
  end

  @impl true
  def after?(_) do
    false
  end

  @impl true
  def transform(dsl_state) do
    translations =
      dsl_state
      |> Transformer.get_entities([:translations])
      |> Enum.reduce(%{}, fn
        %{key: key, translations: translations}, acc ->
          processed_translations = Map.new(translations, &{&1.key, &1.value})

          Map.put(acc, key, processed_translations)
      end)

    dsl_state
    |> Transformer.persist(:translations, translations)
    |> then(&{:ok, &1})
  end
end
