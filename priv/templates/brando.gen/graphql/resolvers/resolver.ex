defmodule <%= app_module %>.<%= domain %>.<%= alias %>Resolver do
  @moduledoc """
  Resolver for <%= plural %>
  """
  use Brando.GraphQL.Resolver,
    context: <%= app_module %>.<%= domain %>,
    schema: <%= app_module %>.<%= domain %>.<%= alias %>
end
