defmodule Brando.Trait.Translatable do
  use Brando.Trait

  attributes do
    attribute :language, :language, required: true
  end
end
