defmodule Brando.Blueprint.Relations.Transformer do
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
    relations = Transformer.get_entities(dsl_state, [:relations])

    {required_relations, optional_relations} =
      Enum.reduce(relations, {[], []}, fn
        %{opts: opts} = rel, {required_relations, optional_relations} ->
          if Map.get(opts, :required) do
            {[Brando.Blueprint.get_relation_key(rel) | required_relations], optional_relations}
          else
            {required_relations, [Brando.Blueprint.get_relation_key(rel) | optional_relations]}
          end
      end)

    dsl_state
    |> set_entries_join_module()
    |> Transformer.persist(:required_relations, required_relations)
    |> Transformer.persist(:optional_relations, optional_relations)
    |> then(&{:ok, &1})
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
