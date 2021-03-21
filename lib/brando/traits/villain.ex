defmodule Brando.Traits.Villain do
  @moduledoc """
  Villain parsing
  """
  use Brando.Trait
  alias Brando.Exception.ConfigError
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  def validate(module, _config) do
    if module.__villain_fields__ == [] do
      raise ConfigError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Traits.Villain, but there are no attributes of type `:villain` found.

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
  def changeset_mutator(module, _config, %{valid?: true}, changeset, _user) do
    Enum.reduce(module.__villain_fields__(), changeset, fn vf, mutated_changeset ->
      Brando.Villain.Schema.generate_html(mutated_changeset, vf.name)
    end)
  end
end
