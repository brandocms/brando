defmodule Brando.Trait.Blocks do
  @moduledoc """
  Blocks
  Only used to register the trait.
  """
  use Brando.Trait

  @impl true
  def validate(_module, _config) do
    raise Brando.Exception.BlueprintError,
      message: """
      trait Brando.Trait.Villain is deprecated

      Use `trait Brando.Trait.Blocks` instead, and also remove your
      :villain fields from the attributes block:

          attributes do
            attribute :data, :villain
          end

      And instead add as a relation:

          relations do
            relation :blocks, :has_many, module: :blocks
          end
      """
  end
end
