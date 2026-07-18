defmodule Brando.Blueprint.Constraints do
  @moduledoc """
  Logic for changeset constraints

  ## Foreign key constraints

  Foreign key constraints are automatically added to the changeset for
  any :belongs_to assocs.

  ## Other constraints

      - `min_length`
      - `max_length`
      - `length`
      - `format` - see `Ecto.Changeset.validate_format/4`
      - `acceptance` - see `Ecto.Changeset.validate_acceptance/3`
      - `confirmation` - see `Ecto.Changeset.validate_confirmation/3`

  ## Block field constraints

      - `require_blocks` - list of module classes that must be present in the block field

  ### Example

      relations do
        relation :blocks, :has_many,
          module: :blocks,
          constraints: [require_blocks: ["header"]]
      end

  This validates that at least one block using a module with class `"header"` is present
  when the block field is saved. Validation is skipped for drafts and when blocks are not
  being cast (i.e., when only other fields are being updated).
  """
  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Blueprint.AssociationKey
  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.RuntimeConfig

  @content_module Module.concat(["Brando", "Content", "Module"])

  def run_validations(changeset, _module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :constraints, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{constraints: constraints}} = attr, new_changeset ->
        constraints_map = Map.new(constraints)

        Enum.reduce(constraints_map, new_changeset, fn constraint, validated_changeset ->
          run_validation(constraint, validated_changeset, attr)
        end)
    end)
  end

  def run_fk_constraints(changeset, _module, []), do: changeset

  def run_fk_constraints(changeset, module, relations) do
    if module.__schema__(:source) do
      relations
      |> Enum.filter(&(&1.type == :belongs_to))
      |> Enum.reduce(changeset, &add_foreign_key_constraint/2)
    else
      changeset
    end
  end

  defp add_foreign_key_constraint(relation, changeset) do
    field = AssociationKey.for(relation)

    foreign_key_constraint(
      changeset,
      field,
      foreign_key_constraint_opts(relation, changeset, field)
    )
  end

  defp foreign_key_constraint_opts(%{opts: %{constraint_name: constraint_name}}, _changeset, _field),
    do: [name: DatabaseIdentifier.normalize(constraint_name)]

  defp foreign_key_constraint_opts(
         _relation,
         %Ecto.Changeset{data: %{__meta__: %{source: source}, __struct__: schema}},
         field
       )
       when is_binary(source) do
    field_source = schema.__schema__(:field_source, field) || field
    [name: DatabaseIdentifier.foreign_key_name(source, field_source)]
  end

  defp foreign_key_constraint_opts(_relation, _changeset, _field), do: []

  defp run_validation({:min_length, length}, validated_changeset, %{name: name, type: :entries}) do
    validate_length(validated_changeset, name, min: length)
  end

  defp run_validation({:min_length, min_length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, min: min_length)

  defp run_validation({:max_length, length}, validated_changeset, %{name: name, type: :entries}) do
    validate_length(validated_changeset, name, max: length)
  end

  defp run_validation({:max_length, max_length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, max: max_length)

  defp run_validation({:length, length}, validated_changeset, %{name: name, type: :entries}) do
    validate_length(validated_changeset, name, is: length)
  end

  defp run_validation({:length, length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, is: length)

  defp run_validation({:format, format}, validated_changeset, %{name: name}),
    do: validate_format(validated_changeset, name, format)

  defp run_validation({:acceptance, true}, validated_changeset, %{name: name}),
    do: validate_acceptance(validated_changeset, name)

  defp run_validation({:confirmation, true}, validated_changeset, %{name: name}),
    do: validate_confirmation(validated_changeset, name)

  defp run_validation({:require_blocks, required_classes}, changeset, %{name: name, opts: %{module: :blocks}}) do
    # Skip validation for drafts
    if Ecto.Changeset.get_field(changeset, :status) == :draft do
      changeset
    else
      assoc_field = :"entry_#{name}"
      validate_required_blocks(changeset, assoc_field, required_classes)
    end
  end

  defp validate_required_blocks(changeset, assoc_field, required_classes) do
    case Ecto.Changeset.get_change(changeset, assoc_field) do
      nil ->
        # Blocks not being changed, skip validation
        changeset

      entry_block_changesets ->
        entry_block_changesets
        |> extract_block_module_ids()
        |> validate_required_modules(changeset, assoc_field, required_classes)
    end
  end

  defp validate_required_modules([], changeset, assoc_field, required_classes) when required_classes != [] do
    Enum.reduce(required_classes, changeset, fn required_class, validated_changeset ->
      add_required_block_error(validated_changeset, assoc_field, required_class)
    end)
  end

  defp validate_required_modules(module_ids, changeset, assoc_field, required_classes) do
    content_module = @content_module

    classes =
      RuntimeConfig.get(:repo_module).all(
        from module in content_module,
          where: module.id in ^module_ids,
          select: module.class
      )

    Enum.reduce(required_classes, changeset, fn required_class, validated_changeset ->
      validate_required_class(validated_changeset, assoc_field, required_class, classes)
    end)
  end

  defp validate_required_class(changeset, assoc_field, required_class, classes) do
    if required_class in classes do
      changeset
    else
      add_required_block_error(changeset, assoc_field, required_class)
    end
  end

  defp add_required_block_error(changeset, assoc_field, required_class) do
    add_error(changeset, assoc_field, "is missing required block: %{class}",
      class: required_class,
      validation: :require_blocks
    )
  end

  defp extract_block_module_ids(entry_block_changesets) do
    entry_block_changesets
    |> Enum.reject(&(&1.action == :delete))
    |> Enum.map(fn eb_cs ->
      case Ecto.Changeset.get_field(eb_cs, :block) do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        %{active: false} -> nil
        %{module_id: module_id} -> module_id
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
