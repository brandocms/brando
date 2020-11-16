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
  Duplicate template
  """
  def duplicate_template(%{template_id: template_id}, %{context: %{current_user: _}}),
    do: Villain.duplicate_template(template_id)

  @doc """
  Get all templates
  """
  def all_templates(args, %{context: %{current_user: _current_user}}) do
    Villain.list_templates(args)
  end

  @doc """
  Find template
  """
  def find_template(%{template_id: template_id}, %{context: %{current_user: _current_user}}) do
    Villain.get_template(%{matches: %{id: template_id}})
  end

  @doc """
  Delete template
  """
  def delete_template(%{template_id: template_id}, %{context: %{current_user: _current_user}}) do
    Villain.delete_template(template_id)
  end

  @doc """
  Create template
  """
  def create_template(%{template_params: template_params}, %{
        context: %{current_user: _current_user}
      }) do
    Villain.create_template(template_params)
  end

  @doc """
  Update template
  """
  def update_template(%{template_id: template_id, template_params: template_params}, %{
        context: %{current_user: _current_user}
      }) do
    Villain.update_template(template_id, template_params)
  end
end
