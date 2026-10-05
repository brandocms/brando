defmodule Brando.Trait.Creator.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, config) do
    required = Keyword.get(config, :required, true)

    quote do
      attributes do
        attribute :edited_at, :datetime
      end

      relations do
        relation :creator, :belongs_to, module: Brando.Users.User, required: unquote(required)
        relation :updated_by, :belongs_to, module: Brando.Users.User
      end
    end
  end
end
