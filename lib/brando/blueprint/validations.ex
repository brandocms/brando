defmodule Brando.Blueprint.Validations do
  import Ecto.Changeset

  def run_validations(changeset, _module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :validate, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{validate: validations}} = attr, new_changeset ->
        validations_map = Enum.into(validations, %{})

        Enum.reduce(validations_map, new_changeset, fn validation, validated_changeset ->
          run_validation(validation, validated_changeset, attr)
        end)
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
