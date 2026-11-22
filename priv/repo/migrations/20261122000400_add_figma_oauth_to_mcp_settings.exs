defmodule BrandoIntegration.Repo.Migrations.AddFigmaOAuthToMCPSettings do
  use Ecto.Migration

  # Mirrors the brando_242 upgrade migration for the test schema.
  @moduledoc """
  The site environment's Figma app and its OAuth connection on
  `mcp_settings` (`Brando.Figma.OAuth`).
  """

  def change do
    alter table(:mcp_settings) do
      add :figma_client_id, :binary
      add :figma_client_id_hint, :text
      add :figma_client_secret, :binary
      add :figma_app_set_at, :utc_datetime_usec
      add :figma_app_set_by_id, references(:users, on_delete: :nilify_all)
      add :figma_oauth_access_token, :binary
      add :figma_oauth_refresh_token, :binary
      add :figma_oauth_expires_at, :utc_datetime_usec
      add :figma_oauth_handle, :text
      add :figma_oauth_connected_at, :utc_datetime_usec
      add :figma_oauth_connected_by_id, references(:users, on_delete: :nilify_all)
      add :figma_oauth_needs_reconnect, :boolean, default: false, null: false
      add :figma_oauth_state_hash, :binary
      add :figma_oauth_pending, :binary
    end
  end
end
