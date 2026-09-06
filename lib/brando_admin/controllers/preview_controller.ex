defmodule Brando.PreviewController do
  @moduledoc """
  Controller for shared ephemeral previews
  """
  use BrandoAdmin, :controller

  alias Brando.Sites
  alias Brando.Utils

  action_fallback BrandoWeb.FallbackController

  @doc false
  def show(conn, %{"preview_key" => preview_key}) do
    preview_opts = %{matches: %{preview_key: preview_key}}

    with {:ok, preview} <- Sites.get_preview(preview_opts),
         :gt <- DateTime.compare(preview.expires_at, DateTime.utc_now()) do
      html(conn, Utils.binary_to_term(preview.html))
    else
      {:error, _} = error -> error
      _ -> {:error, {:preview, :not_found}}
    end
  end
end
