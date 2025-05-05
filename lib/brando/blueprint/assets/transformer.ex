defmodule Brando.Blueprint.Assets.Transformer do
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
    entities = Transformer.get_entities(dsl_state, [:assets])

    # persist each asset
    dsl_state =
      Enum.reduce(entities, dsl_state, fn entity, updated_dsl_state ->
        Transformer.persist(updated_dsl_state, {:asset, entity.name}, entity)
      end)

    processed_assets =
      Enum.reduce(entities, %{required: [], optional: [], castable: [], castable_required: []}, fn
        rel, acc ->
          relation_key = Brando.Blueprint.get_relation_key(rel)

          acc
          |> maybe_add_castable_asset(rel, relation_key)
          |> maybe_add_required_asset()
          |> maybe_add_castable_required_asset()
      end)

    dsl_state
    |> Transformer.persist(:required_assets, processed_assets.required)
    |> Transformer.persist(:optional_assets, processed_assets.optional)
    |> Transformer.persist(:castable_assets, processed_assets.castable)
    |> Transformer.persist(:castable_required_assets, processed_assets.castable_required)
    |> then(&{:ok, &1})
  end

  defp maybe_add_castable_asset(acc, %{type: :gallery} = relation, relation_key) do
    {false, acc, relation, relation_key}
  end

  defp maybe_add_castable_asset(acc, relation, relation_key) do
    {true, %{acc | castable: [relation_key | acc.castable]}, relation, relation_key}
  end

  defp maybe_add_required_asset({status, acc, %{opts: %{required: true}} = relation, relation_key}) do
    {status, true, %{acc | required: [relation_key | acc.required]}, relation, relation_key}
  end

  defp maybe_add_required_asset({status, acc, relation, relation_key}) do
    {status, false, acc, relation, relation_key}
  end

  defp maybe_add_castable_required_asset({true, true, acc, _, relation_key}) do
    %{acc | castable_required: [relation_key | acc.castable_required]}
  end

  defp maybe_add_castable_required_asset({_, _, acc, _, _}) do
    acc
  end
end
