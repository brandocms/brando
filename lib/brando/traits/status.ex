defmodule Brando.Traits.Status do
  @moduledoc """
  Adds `deleted_at`
  """
  use Brando.Trait

  attributes do
    attribute :status, :status, required: true
  end
end
