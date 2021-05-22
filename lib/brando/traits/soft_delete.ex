defmodule Brando.Trait.SoftDelete do
  @moduledoc """
  Adds `deleted_at`

  ### Opts

  - `obfuscated_fields` > Fields that should be changed on deletion to free up
  its name for uniqueness -- for instance a slug field. It will try to reset it
  when restoring.

      trait Brando.Trait.SoftDelete, obfuscated_fields: [:slug]
  """
  use Brando.Trait

  attributes do
    attribute :deleted_at, :datetime
  end
end
