defmodule Brando.Notifications do
  @moduledoc """
  Pushes notification toasts to BrandoJS
  """
  def push_mutation(action, identifier, user) do
    Brando.endpoint().broadcast!("admin", "notifications:mutation", %{
      action: action,
      identifier: identifier,
      user: user
    })
  end
end
