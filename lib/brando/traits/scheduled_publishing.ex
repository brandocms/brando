defmodule Brando.Trait.ScheduledPublishing do
  @moduledoc """
  Adds `publish_at`
  """
  use Brando.Trait

  attributes do
    attribute :publish_at, :datetime
  end
end
