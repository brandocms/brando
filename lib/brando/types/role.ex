defmodule Brando.Type.Role do
  use Brando.Type.Enum, [
    :user,
    :editor,
    :admin,
    :superuser
  ]
end
