defmodule <%= base %>.<%= domain %>.<%= alias %>Resolver do
  @moduledoc """
  Resolver for <%= plural %>
  """
  use Brando.Web, :resolver
  alias <%= base %>.<%= domain %>

  @doc """
  Get all <%= plural %>
  """
  def all(_, %{context: %{current_user: _}}) do
    <%= domain %>.list_<%= plural %>()
  end

  @doc """
  Get <%= singular %> by id
  """
  def get(%{<%= singular %>_id: <%= singular %>_id}, %{context: %{current_user: _}}) do
    <%= domain %>.get_<%= singular %>(<%= singular %>_id)
  end

  @doc """
  Create <%= singular %>
  """
  def create(%{<%= singular %>_params: <%= singular %>_params}, %{context: %{current_user: _}}) do
    <%= domain %>.create_<%= singular %>(<%= singular %>_params)
  end

  @doc """
  Update <%= singular %>
  """
  def update(%{<%= singular %>_id: <%= singular %>_id, <%= singular %>_params: <%= singular %>_params}, %{context: %{current_user: _}}) do
    <%= domain %>.update_<%= singular %>(<%= singular %>_id, <%= singular %>_params)
  end

  @doc """
  Delete <%= singular %>
  """
  def delete(%{<%= singular %>_id: <%= singular %>_id}, %{context: %{current_user: _}}) do
    <%= domain %>.delete_<%= singular %>(<%= singular %>_id)
  end
end
