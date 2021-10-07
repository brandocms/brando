defmodule Brando.Blueprint.Constraints do
  import Ecto.Changeset

  def run_validations(changeset, _module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :constraints, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{constraints: constraints}} = attr, new_changeset ->
        constraints_map = Enum.into(constraints, %{})

        Enum.reduce(constraints_map, new_changeset, fn constraint, validated_changeset ->
          run_validation(constraint, validated_changeset, attr)
        end)
    end)
  end

  def run_fk_constraints(changeset, _module, []), do: changeset

  def run_fk_constraints(changeset, _module, relations) do
    relations
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Enum.reduce(changeset, fn relation, validated_changeset ->
      foreign_key_constraint(validated_changeset, :"#{relation.name}_id")
    end)
  end

  defp run_validation({:min_length, min_length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, min: min_length)

  defp run_validation({:max_length, max_length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, max: max_length)

  defp run_validation({:length, length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, is: length)

  defp run_validation({:format, format}, validated_changeset, %{name: name}),
    do: validate_format(validated_changeset, name, format)

  defp run_validation({:acceptance, true}, validated_changeset, %{name: name}),
    do: validate_acceptance(validated_changeset, name)

  defp run_validation({:confirmation, true}, validated_changeset, %{name: name}),
    do: validate_confirmation(validated_changeset, name)
end
