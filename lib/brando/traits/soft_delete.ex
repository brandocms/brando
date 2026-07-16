defmodule Brando.Trait.SoftDelete do
  @moduledoc """
  Adds `deleted_at`

  ### Opts

  - `obfuscated_fields` > Fields that should be changed on deletion to free up
  its name for uniqueness -- for instance a slug field. It will try to reset it
  when restoring.

      trait :soft_delete, obfuscated_fields: [:slug]
  """
  use Brando.Trait

  alias Brando.Trait.SoftDelete.Compiler

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)
end
