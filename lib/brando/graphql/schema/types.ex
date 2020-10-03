defmodule Brando.Schema.Types do
  use Brando.Web, :absinthe

  # brando types
  import_types Brando.Schema.Types.Files
  import_types Brando.Schema.Types.Identity
  import_types Brando.Schema.Types.Images
  import_types Brando.Schema.Types.Navigation
  import_types Brando.Schema.Types.Page
  import_types Brando.Schema.Types.PageFragment
  import_types Brando.Schema.Types.Scalar
  import_types Brando.Schema.Types.User
  import_types Brando.Schema.Types.Video
end
