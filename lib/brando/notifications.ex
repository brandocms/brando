defmodule Brando.Notifications do
  @moduledoc """
  Pushes notification toasts to BrandoJS
  """
  alias BrandoAdmin.Toast

  def push_mutation(action, identifier, user) do
    payload = %{
      action: action,
      identifier: identifier,
      user: user
    }

    Toast.send(payload, %{type: :mutation})
  end
end
