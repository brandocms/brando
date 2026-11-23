defmodule Brando.Trait.ValidateMediaDrop do
  @moduledoc """
  Validates a module's `media_drop` setting (`Brando.Content.Module.validate_media_drop/1`).
  """
  use Brando.Trait

  def changeset_mutator(_, _, changeset, _, opts) do
    Brando.Content.Module.validate_media_drop(changeset, opts)
  end
end
