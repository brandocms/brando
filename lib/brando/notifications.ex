defmodule Brando.Notifications do
  @moduledoc """
  Pushes notification toasts to BrandoJS
  """
  alias BrandoAdmin.Toast

  def push_mutation(action, identifier, :system) do
    payload = %{
      action: action,
      identifier: identifier,
      user: :system
    }

    Toast.send(payload, %{type: :mutation})
  end

  def push_mutation(action, identifier, user) do
    payload = %{
      action: action,
      identifier: identifier,
      # Goes to everyone who may read the entry: what the toast shows, no more.
      user: %{name: user.name}
    }

    Toast.send(payload, %{type: :mutation})
  end
end
