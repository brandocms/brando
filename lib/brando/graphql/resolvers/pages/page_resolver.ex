defmodule Brando.Pages.PageResolver do
  @moduledoc """
  Resolver for Pages
  """
  use Brando.Web, :resolver
  alias Brando.Pages
  alias Brando.Villain

  @doc """
  Find page
  """
  def find(%{page_id: page_id}, %{context: %{current_user: _current_user}}) do
    Pages.get_page(%{matches: %{id: page_id}})
  end

  @doc """
  Get all pages (at parent level)
  """
  def all(args, %{context: %{current_user: _current_user}}) do
    Pages.list_pages(args)
  end

  @doc """
  Create page
  """
  def create(%{page_params: page_params}, %{context: %{current_user: current_user}}) do
    Pages.create_page(page_params, current_user)
  end

  @doc """
  Update page
  """
  def update(%{page_id: page_id, page_params: page_params}, %{
        context: %{current_user: current_user}
      }) do
    Pages.update_page(page_id, page_params, current_user)
  end

  @doc """
  Delete page
  """
  def delete(%{page_id: page_id}, %{context: %{current_user: _current_user}}) do
    Pages.delete_page(page_id)
  end

  @doc """
  Duplicate page
  """
  def duplicate(%{page_id: page_id}, %{context: %{current_user: _}}),
    do: Pages.duplicate_page(page_id)

  @doc """
  Duplicate section
  """
  def duplicate_section(%{section_id: section_id}, %{context: %{current_user: _}}),
    do: Pages.duplicate_page_fragment(section_id)

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
  def find_module(%{module_id: module_id}, %{context: %{current_user: _current_user}}) do
    Villain.get_module(%{matches: %{id: module_id}})
  end

  @doc """
  Delete module
  """
  def delete_module(%{module_id: module_id}, %{context: %{current_user: _current_user}}) do
    Villain.delete_module(module_id)
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
