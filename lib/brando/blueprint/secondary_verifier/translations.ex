defmodule Brando.Blueprint.SecondaryVerifier.Translations do
  @moduledoc false

  alias Brando.Blueprint.SecondaryVerifier.Support
  alias Spark.Dsl.Verifier

  @doc false
  def verify(dsl_state) do
    contexts = Verifier.get_entities(dsl_state, [:translations])

    with :ok <- verify_unique_contexts(dsl_state, contexts) do
      Support.validate_entities(contexts, &verify_context(dsl_state, &1))
    end
  end

  defp verify_unique_contexts(dsl_state, contexts) do
    case Support.find_duplicate(contexts, & &1.key) do
      nil ->
        :ok

      context ->
        Support.error(
          dsl_state,
          [:translations, context.key],
          context,
          "translation context #{inspect(context.key)} is declared more than once"
        )
    end
  end

  defp verify_context(dsl_state, context) do
    path = [:translations, context.key]

    with :ok <- Support.verify_key(dsl_state, path, context, "translation context", context.key) do
      case Support.find_duplicate(context.translations, & &1.key) do
        nil ->
          Support.validate_entities(context.translations, &verify_translation(dsl_state, context, &1))

        translation ->
          Support.error(
            dsl_state,
            path ++ [translation.key],
            translation,
            "translation key #{inspect(translation.key)} is declared more than once in #{inspect(context.key)}"
          )
      end
    end
  end

  defp verify_translation(dsl_state, context, translation) do
    Support.verify_key(
      dsl_state,
      [:translations, context.key, translation.key],
      translation,
      "translation",
      translation.key
    )
  end
end
