defmodule <%= application_module %>.Schema.Types do
  use <%= application_module %>Web, :absinthe

  # absinthe types
  import_types Absinthe.Plug.Types

  # import app types
  # import_types <%= application_module %>.Schema.Types.Example
end
