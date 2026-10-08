defmodule Brando.Trait.ScheduledPublishing.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote do
      attributes do
        attribute :publish_at, :datetime
        attribute :unpublish_at, :datetime
      end
    end
  end
end
