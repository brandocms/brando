defmodule Brando.Content.Identifier.Registry do
  @moduledoc """
  Registry for blueprints that have persistent identifiers.

  Provides a single source of truth for determining which blueprints
  have identifiers enabled and should be persisted to the database.
  """

  @doc """
  Returns all blueprint modules that have persistent identifiers.

  This filters blueprints that:
  1. Have `__has_identifier__/0` returning `true`
  2. Have `__persist_identifier__/0` returning `true`

  ## Options

  - Pass `:include_brando` to include Brando's built-in schemas (Page, Fragment, etc.)

  ## Examples

      iex> list_persistent_identifier_modules()
      [MyApp.Projects.Project, MyApp.Blog.Article]

      iex> list_persistent_identifier_modules(:include_brando)
      [Brando.Pages.Page, Brando.Pages.Fragment, MyApp.Projects.Project]
  """
  @spec list_persistent_identifier_modules() :: [module()]
  def list_persistent_identifier_modules do
    Brando.Blueprint.list_blueprints()
    |> filter_persistent_identifier_modules()
  end

  @spec list_persistent_identifier_modules(:include_brando) :: [module()]
  def list_persistent_identifier_modules(:include_brando) do
    :include_brando
    |> Brando.Blueprint.list_blueprints()
    |> filter_persistent_identifier_modules()
  end

  @doc """
  Checks if a module has a persistent identifier.

  Returns `true` if the module has both `__has_identifier__/0` returning `true`
  and `__persist_identifier__/0` returning `true`.

  ## Examples

      iex> has_persistent_identifier?(MyApp.Projects.Project)
      true

      iex> has_persistent_identifier?(Brando.Content.Var)
      false
  """
  @spec has_persistent_identifier?(module()) :: boolean()
  def has_persistent_identifier?(module) do
    Brando.Content.has_identifier(module) == {:ok, :has_identifier} &&
      Brando.Content.persist_identifier(module) == {:ok, :persist_identifier}
  end

  defp filter_persistent_identifier_modules(modules) do
    Enum.filter(modules, &has_persistent_identifier?/1)
  end
end
