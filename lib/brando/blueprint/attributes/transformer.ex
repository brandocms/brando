defmodule Brando.Blueprint.Attributes.Transformer do
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias Brando.Blueprint.Attributes

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
    module = Transformer.get_persisted(dsl_state, :module)
    allow_mark_as_deleted? = Module.get_attribute(module, :allow_mark_as_deleted)

    dsl_state =
      dsl_state
      |> maybe_add_marked_as_deleted_attribute(allow_mark_as_deleted?)
      |> sort_attributes()

    entities = Transformer.get_entities(dsl_state, [:attributes])

    # persist each attribute
    dsl_state =
      Enum.reduce(entities, dsl_state, fn entity, updated_dsl_state ->
        Transformer.persist(updated_dsl_state, entity.name, entity)
      end)

    {required_attrs, optional_attrs} =
      Enum.reduce(entities, {[], []}, fn
        %{name: name, opts: opts}, {required_attrs, optional_attrs} ->
          if Map.get(opts, :required) do
            {[name | required_attrs], optional_attrs}
          else
            {required_attrs, [name | optional_attrs]}
          end
      end)

    dsl_state
    |> Transformer.persist(:required_attrs, Enum.sort(required_attrs))
    |> Transformer.persist(:optional_attrs, Enum.sort(optional_attrs))
    |> then(&{:ok, &1})
  end

  def sort_attributes(dsl_state) do
    attributes = Transformer.get_entities(dsl_state, [:attributes])

    end_attrs = [
      :inserted_at,
      :updated_at,
      :deleted_at,
      :creator_id,
      :sequence,
      :marked_as_deleted,
      :meta_title,
      :meta_description
    ]

    {normal_attrs, attrs_to_move} =
      Enum.split_with(attributes, fn attr ->
        attr.name not in end_attrs
      end)

    sorted_attributes = normal_attrs ++ attrs_to_move

    Enum.reduce(sorted_attributes, dsl_state, fn attribute, updated_dsl_state ->
      updated_dsl_state
      |> Transformer.remove_entity([:attributes], &(&1.name == attribute.name))
      |> Transformer.add_entity([:attributes], attribute)
    end)
  end

  defp maybe_add_marked_as_deleted_attribute(dsl_state, true) do
    new_attr = %Attributes.Attribute{
      name: :marked_as_deleted,
      type: :boolean,
      opts: %{default: false, virtual: true}
    }

    Transformer.add_entity(dsl_state, [:attributes], new_attr)
  end

  defp maybe_add_marked_as_deleted_attribute(dsl_state, _), do: dsl_state
end
