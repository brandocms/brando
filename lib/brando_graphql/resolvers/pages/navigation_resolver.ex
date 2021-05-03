defmodule Brando.Navigation.NavigationResolver do
  @moduledoc """
  Resolver for Navigation
  """
  use BrandoWeb, :resolver
  alias Brando.Navigation

  @doc """
  Find menu
  """
  def find_menu(%{menu_id: menu_id}, %{context: %{current_user: _current_user}}) do
    Navigation.get_menu(String.to_integer(menu_id))
  end

  @doc """
  Get all menus (at parent level)
  """
  def all_menus(args, %{context: %{current_user: _current_user}}) do
    Navigation.list_menus(args)
  end

  @doc """
  Create menu
  """
  def create_menu(%{menu_params: menu_params}, %{context: %{current_user: current_user}}) do
    menu_params
    |> Navigation.create_menu(current_user)
  end

  @doc """
  Update menu
  """
  def update_menu(%{menu_id: menu_id, menu_params: menu_params}, %{
        context: %{current_user: current_user}
      }) do
    menu_id
    |> Navigation.update_menu(menu_params, current_user)
  end

  @doc """
  Delete menu
  """
  def delete_menu(%{menu_id: menu_id}, %{context: %{current_user: _current_user}}) do
    Navigation.delete_menu(menu_id)
  end

  @doc """
  Duplicate menu
  """
  def duplicate_menu(%{menu_id: menu_id}, %{context: %{current_user: _}}),
    do: Navigation.duplicate_menu(menu_id)
end
