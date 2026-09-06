defmodule Brando.Authorization.Snapshot do
  @moduledoc """
  A permission snapshot for repeated UI checks within a single render.

  Context operations must call `authorize/3` with a Scope instead; they reload
  authority. Keeping a Snapshot in a long-lived socket is not authorization.
  """
  defstruct [:scope, :user, :reason, grants: %{}, superuser?: false]
end
