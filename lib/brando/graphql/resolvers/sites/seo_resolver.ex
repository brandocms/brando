defmodule Brando.Sites.SEOResolver do
  @moduledoc """
  Resolver for seos
  """
  use Brando.Web, :resolver
  alias Brando.Sites

  @doc """
  Get seo by id
  """
  def get(_, %{context: %{current_user: _}}) do
    Sites.get_seo()
  end

  @doc """
  Create seo
  """
  def create(%{seo_params: seo_params}, %{context: %{current_user: user}}) do
    Sites.create_seo(seo_params, user)
  end

  @doc """
  Update seo
  """
  def update(%{seo_params: seo_params}, %{
        context: %{current_user: user}
      }) do
    Sites.update_seo(seo_params, user)
  end
end
