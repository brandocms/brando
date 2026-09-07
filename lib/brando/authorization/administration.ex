defmodule Brando.Authorization.Administration do
  @moduledoc """
  Authority for preparing groups before cutover and managing them afterwards.

  Only an active legacy Superuser can prepare group configuration in legacy mode.
  This exception belongs to group administration; it never changes the application
  resolver or gives group members authority before the configuration switch.
  """
  alias Brando.Authorization.{Engine, Scope, Snapshot}

  def snapshot(%Scope{} = scope) do
    snapshot = Engine.snapshot(scope)

    cond do
      Engine.enabled?() -> snapshot
      snapshot.reason -> snapshot
      snapshot.user.role == :superuser -> %{snapshot | superuser?: true}
      true -> %{snapshot | reason: :groups_not_enabled, superuser?: false}
    end
  end

  def can?(scope, action, subject), do: Engine.can?(snapshot(scope), action, subject)

  def authorize(scope, action, subject),
    do: if(can?(scope, action, subject), do: :ok, else: {:error, :forbidden})

  def superuser?(scope) do
    match?(%Snapshot{reason: nil, superuser?: true}, snapshot(scope))
  end
end
