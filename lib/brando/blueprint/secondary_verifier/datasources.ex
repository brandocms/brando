defmodule Brando.Blueprint.SecondaryVerifier.Datasources do
  @moduledoc false

  alias Brando.Blueprint.SecondaryVerifier.Support
  alias Spark.Dsl.Verifier

  @doc false
  def verify(dsl_state) do
    datasources = Verifier.get_entities(dsl_state, [:datasources])

    with :ok <- verify_unique_keys(dsl_state, datasources) do
      Support.validate_entities(datasources, &verify_datasource(dsl_state, &1))
    end
  end

  defp verify_unique_keys(dsl_state, datasources) do
    case Support.find_duplicate(datasources, & &1.key) do
      nil ->
        :ok

      datasource ->
        Support.error(
          dsl_state,
          [:datasources, datasource.key],
          datasource,
          "datasource #{inspect(datasource.key)} is declared more than once"
        )
    end
  end

  defp verify_datasource(dsl_state, datasource) do
    path = [:datasources, datasource.key]

    with :ok <- Support.verify_key(dsl_state, path, datasource, "datasource", datasource.key),
         :ok <- verify_callbacks(dsl_state, datasource),
         :ok <- verify_unique_meta_keys(dsl_state, datasource) do
      Support.validate_entities(datasource.meta, &verify_meta(dsl_state, datasource, &1))
    end
  end

  defp verify_callbacks(dsl_state, %{type: :list, list: nil} = datasource) do
    datasource_error(dsl_state, datasource, "a `:list` datasource requires a `list` callback")
  end

  defp verify_callbacks(dsl_state, %{type: :selection, list: nil} = datasource) do
    datasource_error(dsl_state, datasource, "a `:selection` datasource requires a `list` callback")
  end

  defp verify_callbacks(dsl_state, %{type: :selection, get: nil} = datasource) do
    datasource_error(dsl_state, datasource, "a `:selection` datasource requires a `get` callback")
  end

  defp verify_callbacks(dsl_state, %{type: :single, get: nil} = datasource) do
    datasource_error(dsl_state, datasource, "a `:single` datasource requires a `get` callback")
  end

  defp verify_callbacks(_dsl_state, _datasource), do: :ok

  defp verify_unique_meta_keys(dsl_state, datasource) do
    case Support.find_duplicate(datasource.meta, & &1.key) do
      nil ->
        :ok

      meta ->
        Support.error(
          dsl_state,
          [:datasources, datasource.key, :meta, meta.key],
          meta,
          "datasource #{inspect(datasource.key)} declares meta key #{inspect(meta.key)} more than once"
        )
    end
  end

  defp verify_meta(dsl_state, datasource, meta) do
    path = [:datasources, datasource.key, :meta, meta.key]

    with :ok <- Support.verify_key(dsl_state, path, meta, "datasource meta", meta.key) do
      Support.verify_non_empty_string(dsl_state, path, meta, "datasource meta label", meta.label)
    end
  end

  defp datasource_error(dsl_state, datasource, message) do
    Support.error(dsl_state, [:datasources, datasource.key], datasource, message)
  end
end
