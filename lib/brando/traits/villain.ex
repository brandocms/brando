defmodule Brando.Trait.Villain do
  @moduledoc """
  Villain parsing
  """
  use Brando.Trait
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @impl true
  def validate(module, _config) do
    if Enum.filter(module.__attributes__(), &(&1.type == :villain)) != [] do
      raise Brando.Exception.BlueprintError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Trait.Villain, but there are attributes with type `:villain` found.

        Remove your :villain fields from the attributes block

            attributes do
              attribute :data, :villain
            end

        And instead add as a relation

            relations do
              relation :blocks, :has_many, module: :blocks
            end
        """
    end

    if module.__villain_fields__() == [] do
      raise Brando.Exception.BlueprintError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Trait.Villain, but there are no relations with module `:blocks` found.

            relations do
              relation :blocks, :has_many, module: :blocks
            end
        """
    end

    true
  end
end
