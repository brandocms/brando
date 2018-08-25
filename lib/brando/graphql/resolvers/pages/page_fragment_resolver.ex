defmodule Brando.Pages.PageFragmentResolver do
  @moduledoc """
  Resolver for page fragments
  """
  use Brando.Web, :resolver
  alias Brando.Pages

  @doc """
  Find page
  """
  def find(%{page_fragment_id: page_fragment_id}, %{context: %{current_user: _current_user}}) do
    Pages.get_page_fragment(String.to_integer(page_fragment_id))
  end

  @doc """
  Get all pages (at parent level)
  """
  def all(_, %{context: %{current_user: _current_user}}) do
    Pages.list_page_fragments()
  end

  @doc """
  Create page
  """
  def create(%{page_fragment_params: page_fragment_params}, %{
        context: %{current_user: current_user}
      }) do
    page_fragment_params
    |> Pages.create_page_fragment(current_user)
    |> response
  end

  @doc """
  Update page
  """
  def update(%{page_fragment_id: page_fragment_id, page_fragment_params: page_fragment_params}, _) do
    page_fragment_id
    |> Pages.update_page_fragment(page_fragment_params)
    |> response
  end

  @doc """
  Delete page
  """
  def delete(%{page_fragment_id: page_fragment_id}, %{context: %{current_user: _current_user}}) do
    String.to_integer(page_fragment_id)
    |> Pages.delete_page_fragment()
    |> response
  end
end
