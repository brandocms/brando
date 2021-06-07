defmodule Brando.Trait.Villain do
  @moduledoc """
  Villain parsing
  """
  use Brando.Trait
  alias Brando.Exception.ConfigError
  alias Ecto.Changeset
  alias Brando.Blueprint.Attributes

  @type changeset :: Changeset.t()
  @type config :: list()

  def trait_attributes(attributes, _relations) do
    attributes
    |> Enum.filter(&(&1.type == :villain))
    |> Enum.map(fn
      %{name: :data} ->
        Attributes.build_attr(:html, :text, [])

      %{name: data_name} ->
        data_name
        |> to_string
        |> String.replace("_data", "_html")
        |> String.to_atom()
        |> Attributes.build_attr(:text, [])
    end)
  end

  def validate(module, _config) do
    if module.__villain_fields__ == [] do
      raise ConfigError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Trait.Villain, but there are no attributes of type `:villain` found.

            attributes do
              attribute :data, :villain
            end
        """
    end

    true
  end

  @doc """
  Generate HTML
  """
  @spec changeset_mutator(module, config, changeset, map | :system) :: changeset
  def changeset_mutator(module, _config, changeset, _user) do
    casted_changeset =
      Enum.reduce(module.__villain_fields__(), changeset, fn vf, mutated_changeset ->
        PolymorphicEmbed.cast_polymorphic_embed(mutated_changeset, vf.name)
        # case Map.get(mutated_changeset.params, to_string(vf.name)) do
        #   nil ->
        #     mutated_changeset

        #   params ->
        #     new_params =
        #       Map.put(
        #         mutated_changeset.params,
        #         to_string(vf.name),
        #         transform_indexed_map_to_list(params)
        #       )

        #     Map.put(changeset, :params, new_params)
        # end
        # |> PolymorphicEmbed.cast_polymorphic_embed(vf.name)
      end)

    if casted_changeset.valid? do
      Enum.reduce(module.__villain_fields__(), casted_changeset, fn vf, mutated_changeset ->
        Brando.Villain.Schema.generate_html(mutated_changeset, vf.name)
      end)
    else
      casted_changeset
    end
  end

  def changeset_mutator(_module, _config, changeset, _user), do: changeset

  defp transform_indexed_map_to_list(indexed_map) do
    Enum.map(indexed_map, &elem(&1, 1))
  end
end
