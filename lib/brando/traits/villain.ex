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

  @impl true
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

  @impl true
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
  @impl true
  def changeset_mutator(module, _config, changeset, _user, skip_villain: true) do
    cast_poly(changeset, module.__villain_fields__())
  end

  def changeset_mutator(module, _config, changeset, _user, opts) do
    case cast_poly(changeset, module.__villain_fields__()) do
      %{valid?: true} = casted_changeset ->
        Enum.reduce(module.__villain_fields__(), casted_changeset, fn vf, mutated_changeset ->
          Brando.Villain.Schema.generate_html(mutated_changeset, vf.name)
        end)

      casted_changeset ->
        casted_changeset
    end
  end

  defp cast_poly(changeset, villain_fields) do
    Enum.reduce(villain_fields, changeset, fn vf, mutated_changeset ->
      PolymorphicEmbed.cast_polymorphic_embed(mutated_changeset, vf.name)
    end)
  end

  defp transform_indexed_map_to_list(indexed_map) do
    Enum.map(indexed_map, &elem(&1, 1))
  end
end
