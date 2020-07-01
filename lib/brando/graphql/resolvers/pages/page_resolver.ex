defmodule Brando.Pages.PageResolver do
  @moduledoc """
  Resolver for Pages
  """
  use Brando.Web, :resolver
  alias Brando.Pages

  @doc """
  Find page
  """
  def find(%{page_id: page_id}, %{context: %{current_user: _current_user}}) do
    Pages.get_page(String.to_integer(page_id))
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
    page_params
    |> Pages.create_page(current_user)
    |> response
  end

  @doc """
  Update page
  """
  def update(%{page_id: page_id, page_params: page_params}, %{
        context: %{current_user: current_user}
      }) do
    page_id
    |> Pages.update_page(page_params, current_user)
    |> response
  end

  @doc """
  Delete page
  """
  def delete(%{page_id: page_id}, %{context: %{current_user: _current_user}}) do
    page_id
    |> Pages.delete_page()
    |> response
  end

  @doc """
  Duplicate page
  """
  def duplicate(%{page_id: page_id}, %{context: %{current_user: user}}) do
    page_id
    |> Pages.duplicate_page(user)
    |> response
  end

  @doc """
  Duplicate section
  """
  def duplicate_section(%{section_id: section_id}, %{context: %{current_user: user}}) do
    section_id
    |> Pages.duplicate_page_fragment(user)
    |> response
  end
end
