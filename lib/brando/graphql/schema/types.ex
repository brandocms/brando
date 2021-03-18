defmodule Brando.GraphQL.Schema.Types do
  use Brando.Web, :absinthe

  # brando types
  import_types Brando.GraphQL.Schema.Types.Common
  import_types Brando.GraphQL.Schema.Types.Files
  import_types Brando.GraphQL.Schema.Types.Identity
  import_types Brando.GraphQL.Schema.Types.Images
  import_types Brando.GraphQL.Schema.Types.Navigation
  import_types Brando.GraphQL.Schema.Types.Page
  import_types Brando.GraphQL.Schema.Types.PageFragment
  import_types Brando.GraphQL.Schema.Types.Pagination
  import_types Brando.GraphQL.Schema.Types.Revision
  import_types Brando.GraphQL.Schema.Types.Scalar
  import_types Brando.GraphQL.Schema.Types.SEO
  import_types Brando.GraphQL.Schema.Types.User
  import_types Brando.GraphQL.Schema.Types.Video
end
