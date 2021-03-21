defmodule Brando.Traits.Unique do
  @doc """
  If we have a language field, we check uniqueness against it
  """
  use Brando.Trait
  import Ecto.Query
  import Ecto.Changeset
  alias Brando.Utils.Schema
  alias Brando.Exception.ConfigError

  def validate(module, config) do
    unique_attrs = Keyword.get(config, :attributes)

    if is_nil(unique_attrs) do
      raise ConfigError,
        message: """
        Brando.Traits.Unique is missing its `attributes` config in `#{inspect(module)}`

            trait Brando.Traits.Unique, attributes: [:slug]

        """
    end

    true
  end

  def changeset_mutator(module, config, %{valid?: true} = changeset, _user) do
    unique_attrs = Keyword.get(config, :attributes)

    if is_nil(unique_attrs) do
      raise ConfigError,
        message: """
        Brando.Traits.Unique is missing its `attributes` config.

            trait Brando.Traits.Unique, attributes: [:slug]

        """
    end

    if :language in module.__schema__(:fields) do
      # make the wanted field unique with the language field, so we
      # can have the same slug or uri for different languages
      Schema.avoid_field_collision(module, changeset, unique_attrs, &filter_by_language/2)
    else
      Schema.avoid_field_collision(changeset, unique_attrs)
    end
  end

  def changeset_mutator(_, _, changeset, _), do: changeset

  defp filter_by_language(module, changeset) do
    from m in module,
      where: m.language == ^get_field(changeset, :language)
  end
end
