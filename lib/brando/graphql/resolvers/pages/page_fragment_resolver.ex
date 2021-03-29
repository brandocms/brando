defmodule Brando.Pages.FragmentResolver do
  @moduledoc """
  Resolver for page fragments
  """
  use Brando.Web, :resolver

  use Brando.GraphQL.Resolver,
    schema: Brando.Pages.Fragment,
    context: Brando.Pages
end
