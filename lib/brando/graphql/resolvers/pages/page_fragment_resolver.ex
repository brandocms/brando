defmodule Brando.Pages.PageFragmentResolver do
  @moduledoc """
  Resolver for page fragments
  """
  use Brando.Web, :resolver

  use Brando.GraphQL.Resolver,
    schema: Brando.Pages.PageFragment,
    context: Brando.Pages
end
