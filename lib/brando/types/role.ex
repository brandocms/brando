defmodule Brando.Type.Role do
  @deprecated "Moved to Ecto.Enum"
  use Brando.Type.Enum, [
    :user,
    :editor,
    :admin,
    :superuser
  ]
end
