defmodule BrandoGraphQL.Schema do
  @moduledoc """
  Use this to import GQL queries and mutations
  """

  defmacro __using__(_) do
    quote do
      import BrandoGraphQL.Schema
    end
  end

  def import_brando_dataloaders(dataloader, ctx) do
    dataloader
    |> Dataloader.add_source(Brando.Images, Brando.Images.data(ctx))
    |> Dataloader.add_source(Brando.Navigation, Brando.Navigation.data(ctx))
    |> Dataloader.add_source(Brando.Pages, Brando.Pages.data(ctx))
    |> Dataloader.add_source(Brando.Sites, Brando.Sites.data(ctx))
    |> Dataloader.add_source(Brando.Users, Brando.Users.data(ctx))
  end

  @doc """
  Imports all Brando mutations
  """
  defmacro import_brando_mutations do
    quote do
      # Brando mutations
      import_fields :image_mutations
      import_fields :page_mutations
      import_fields :navigation_mutations
      import_fields :fragment_mutations
      import_fields :user_mutations
      import_fields :identity_mutations
      import_fields :seo_mutations
      import_fields :global_mutations
      import_fields :common_mutations
    end
  end

  @doc """
  Imports all brando queries
  """
  defmacro import_brando_queries do
    quote do
      # Brando queries
      import_fields :image_queries
      import_fields :page_queries
      import_fields :navigation_queries
      import_fields :fragment_queries
      import_fields :user_queries
      import_fields :identity_queries
      import_fields :revision_queries
      import_fields :seo_queries
      import_fields :global_queries
      import_fields :blueprint_queries
    end
  end
end
