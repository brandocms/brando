defmodule Brando.Type.Role do
  use Brando.Type.Enum, [
    :user,
    :staff,
    :admin,
    :superuser
  ]
end
