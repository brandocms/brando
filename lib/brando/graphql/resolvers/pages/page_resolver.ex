defmodule Brando.Pages.PageResolver do
  @moduledoc """
  Resolver for Pages
  """
  use Brando.GraphQL.Resolver,
    context: Brando.Pages,
    schema: Brando.Pages.Page

  alias Brando.Pages
  alias Brando.Villain

  @doc """
  Duplicate page
  """
  def duplicate(%{page_id: page_id}, %{context: %{current_user: user}}),
    do: Pages.duplicate_page(page_id, user)

  @doc """
  Duplicate section
  """
  def duplicate_section(%{section_id: section_id}, %{context: %{current_user: user}}),
    do: Pages.duplicate_page_fragment(section_id, user)

  @doc """
  Duplicate module
  """
  def duplicate_module(%{module_id: module_id}, %{context: %{current_user: _}}),
    do: Villain.duplicate_module(module_id)

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
        context: %{current_user: _current_user}
      }) do
    Villain.create_module(module_params)
  end

  @doc """
  Update module
  """
  def update_module(%{module_id: module_id, module_params: module_params}, %{
        context: %{current_user: _current_user}
      }) do
    Villain.update_module(module_id, module_params)
  end
end
