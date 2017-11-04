defmodule Brando.Schema.Types do
  use Brando.Web, :absinthe

  # brando types
  import_types Brando.Schema.Types.Scalar
  import_types Brando.Schema.Types.User
  import_types Brando.Schema.Types.Images
  import_types Brando.Schema.Types.Page
  import_types Brando.Schema.Types.PageFragment
end
