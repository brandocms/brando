defmodule Brando.Notifications.Recipient do
  @moduledoc false
  # Whether a user an email route names may get a notification: an active
  # account, and, for a notification about an entry, one that may read it
  # (with group authorization). An entry that is gone can no longer be read,
  # and its notification is not sent.

  alias Brando.Repo

  def may_see?(%{active: true, deleted_at: nil} = user, %{entry_schema: schema, entry_id: id})
      when is_binary(schema) and is_integer(id) do
    if Brando.Authorization.enabled?(), do: readable?(user, schema, id), else: true
  end

  def may_see?(%{active: true, deleted_at: nil}, _delivery), do: true
  def may_see?(_user, _delivery), do: false

  defp readable?(user, schema, id) do
    module = String.to_existing_atom(schema)

    case Repo.get(module, id) do
      nil -> false
      entry -> Brando.Authorization.can?(Brando.Authorization.Scope.current(user), :read, entry)
    end
  rescue
    _ -> false
  end
end
