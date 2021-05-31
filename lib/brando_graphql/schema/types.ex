defmodule BrandoGraphQL.Schema.Types do
  use BrandoAdmin, :absinthe

  # brando types
  import_types BrandoGraphQL.Schema.Types.Blueprint
  import_types BrandoGraphQL.Schema.Types.Common
  import_types BrandoGraphQL.Schema.Types.Files
  import_types BrandoGraphQL.Schema.Types.Identity
  import_types BrandoGraphQL.Schema.Types.Images
  import_types BrandoGraphQL.Schema.Types.Navigation
  import_types BrandoGraphQL.Schema.Types.Page
  import_types BrandoGraphQL.Schema.Types.Fragment
  import_types BrandoGraphQL.Schema.Types.Pagination
  import_types BrandoGraphQL.Schema.Types.Revision
  import_types BrandoGraphQL.Schema.Types.Scalar
  import_types BrandoGraphQL.Schema.Types.SEO
  import_types BrandoGraphQL.Schema.Types.User
  import_types BrandoGraphQL.Schema.Types.Video
end
