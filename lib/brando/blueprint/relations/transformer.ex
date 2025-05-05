defmodule Brando.Blueprint.Relations.Transformer do
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
    dsl_state = set_entries_join_module(dsl_state)
    relations = Transformer.get_entities(dsl_state, [:relations])

    # persist each relation
    dsl_state =
      Enum.reduce(relations, dsl_state, fn relation, updated_dsl_state ->
        Transformer.persist(updated_dsl_state, {:relation, relation.name}, relation)
      end)

    processed_relations =
      Enum.reduce(
        relations,
        %{required: [], optional: [], castable: [], castable_required: []},
        fn
          rel, acc ->
            relation_key = Brando.Blueprint.get_relation_key(rel)

            acc
            |> maybe_add_castable_relation(rel, relation_key)
            |> maybe_add_required_relation()
            |> maybe_add_castable_required_relation()
        end
      )

    dsl_state
    |> Transformer.persist(:required_relations, processed_relations.required)
    |> Transformer.persist(:optional_relations, processed_relations.optional)
    |> Transformer.persist(:castable_relations, processed_relations.castable)
    |> Transformer.persist(:castable_required_relations, processed_relations.castable_required)
    |> then(&{:ok, &1})
  end

  defp maybe_add_castable_relation(acc, %{type: :belongs_to} = relation, relation_key) do
    {true, %{acc | castable: [relation_key | acc.castable]}, relation, relation_key}
  end

  defp maybe_add_castable_relation(acc, relation, relation_key) do
    {false, acc, relation, relation_key}
  end

  defp maybe_add_required_relation({status, acc, %{opts: %{required: true}} = relation, relation_key}) do
    {status, true, %{acc | required: [relation_key | acc.required]}, relation, relation_key}
  end

  defp maybe_add_required_relation({status, acc, relation, relation_key}) do
    {status, false, acc, relation, relation_key}
  end

  defp maybe_add_castable_required_relation({true, true, acc, _, relation_key}) do
    %{acc | castable_required: [relation_key | acc.castable_required]}
  end

  defp maybe_add_castable_required_relation({_, _, acc, _, _}) do
    acc
  end

  defp set_entries_join_module(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    dsl_state
    |> Transformer.get_entities([:relations])
    |> Enum.reduce(dsl_state, fn
      %{type: :entries} = relation, dsl_state ->
        join_module =
          Module.concat([
            module,
            "#{Phoenix.Naming.camelize(to_string(relation.name))}Identifier"
          ])

        updated_relation = %{relation | opts: Map.put(relation.opts, :module, join_module)}

        Transformer.replace_entity(
          dsl_state,
          [:relations],
          updated_relation,
          fn replacing ->
            replacing.name == relation.name
          end
        )

      _relation, dsl_state ->
        dsl_state
    end)
  end
end
