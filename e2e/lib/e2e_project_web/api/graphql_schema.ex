defmodule E2eProjectWeb.API.GraphqlSchema do
  @moduledoc "GraphQL schema for the E2E project."
  use BrandoGraphql.Schema,
    schemas: [
      E2eProject.Projects.Project
    ]
end
