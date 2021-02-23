defmodule <%= app_module %>.<%= domain %>.<%= alias %>Resolver do
  @moduledoc """
  Resolver for <%= plural %>
  """
  use Brando.Web, :resolver
  alias <%= app_module %>.<%= domain %>

  @doc """
  Get all <%= plural %>
  """
  def all(args, %{context: %{current_user: _}}) do
    <%= domain %>.list_<%= plural %>(args)
  end

  @doc """
  Get <%= singular %> by args
  """
  def get(args, _) do
    <%= domain %>.get_<%= singular %>(args)
  end

  @doc """
  Create <%= singular %>
  """
  def create(%{<%= singular %>_params: <%= singular %>_params}, %{context: %{current_user: user}}) do
    <%= domain %>.create_<%= singular %>(<%= singular %>_params, user)
  end

  @doc """
  Update <%= singular %>
  """
  def update(%{<%= singular %>_id: <%= singular %>_id, <%= singular %>_params: <%= singular %>_params}, %{context: %{current_user: user}}) do
    <%= domain %>.update_<%= singular %>(<%= singular %>_id, <%= singular %>_params, user)
  end

  @doc """
  Delete <%= singular %>
  """
  def delete(%{<%= singular %>_id: <%= singular %>_id}, %{context: %{current_user: _}}) do
    <%= domain %>.delete_<%= singular %>(<%= singular %>_id)
  end
end
