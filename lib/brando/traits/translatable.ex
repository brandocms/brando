defmodule Brando.Traits.Translatable do
  use Brando.Trait

  attributes do
    attribute :language, :language
  end

  def migration_index(_table) do
    """
    """
  end
end
