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
  Add creator to changeset
  """
  @spec changeset_mutator(module, config, changeset, map | :system) :: changeset
  def changeset_mutator(module, _config, %{valid?: true} = changeset, _user) do
    Enum.reduce(module.__villain_fields__(), changeset, fn vf, mutated_changeset ->
      Brando.Villain.Schema.generate_html(mutated_changeset, vf.name)
    end)
  end
end
