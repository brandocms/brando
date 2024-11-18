defmodule Brando.Blueprint.Assets.Transformer do
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
        Transformer.persist(updated_dsl_state, entity.name, entity)
      end)

    {required_assets, optional_assets} =
      Enum.reduce(entities, {[], []}, fn
        %{name: name, opts: opts}, {required_assets, optional_assets} ->
          if Map.get(opts, :required) do
            {[name | required_assets], optional_assets}
          else
            {required_assets, [name | optional_assets]}
          end
      end)

    dsl_state
    |> Transformer.persist(:required_assets, required_assets)
    |> Transformer.persist(:optional_assets, optional_assets)
    |> then(&{:ok, &1})
  end
end
