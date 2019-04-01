defmodule <%= application_module %>.Schema.Types do
  @moduledoc """
  Absinthe schema types
  """

  use <%= application_module %>Web, :absinthe

  # absinthe types
  import_types Absinthe.Plug.Types

  #++types
  #__types
end
