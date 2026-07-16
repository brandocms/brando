defmodule Brando.Trait.Creator.Compiler do
  @moduledoc false

  @doc false
  def generate_code(_module, _config) do
    quote do
      relations do
        relation :creator, :belongs_to, module: Brando.Users.User, required: true
      end
    end
  end
end
