defmodule Brando.Pages.PageResolver do
  @moduledoc """
  Resolver for Pages
  """
  use BrandoGraphQL.Resolver,
    context: Brando.Pages,
    schema: Brando.Pages.Page

  alias Brando.Villain

  @doc """
  Duplicate module
  """
  def duplicate_module(%{module_id: module_id}, %{context: %{current_user: user}}),
    do: Villain.duplicate_module(module_id, user)

  @doc """
  Get all modules
  """
  def all_modules(args, %{context: %{current_user: _current_user}}) do
    Villain.list_modules(args)
  end

  @doc """
  Find module
  """
  def get_module(%{module_id: module_id}, %{context: %{current_user: _current_user}}) do
    Villain.get_module(%{matches: %{id: module_id}})
  end

  @doc """
  Delete module
  """
  def delete_module(%{module_id: module_id}, %{context: %{current_user: user}}) do
    Villain.delete_module(module_id, user)
  end

  @doc """
  Create module
  """
  def create_module(%{module_params: module_params}, %{
        context: %{current_user: user}
      }) do
    Villain.create_module(module_params, user)
  end

  @doc """
  Update module
  """
  def update_module(%{module_id: module_id, module_params: module_params}, %{
        context: %{current_user: user}
      }) do
    Villain.update_module(module_id, module_params, user)
  end
end
