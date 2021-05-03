defmodule Brando.Pages.FragmentResolver do
  @moduledoc """
  Resolver for page fragments
  """
  use BrandoWeb, :resolver

  use BrandoGraphQL.Resolver,
    schema: Brando.Pages.Fragment,
    context: Brando.Pages
end
