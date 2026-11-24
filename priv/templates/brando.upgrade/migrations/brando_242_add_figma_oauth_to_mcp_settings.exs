defmodule Brando.Repo.Migrations.Brando242AddFigmaOAuthToMCPSettings do
  use Ecto.Migration

  @moduledoc """
  Connecting Figma with OAuth on `mcp_settings`, per site environment
  (`Brando.Figma.OAuth`):

    * the site environment's Figma app: `figma_client_id` and
      `figma_client_secret`, encrypted with `Brando.Crypto`, the client id's
      last four characters (`figma_client_id_hint`), and when and by whom it
      was saved;
    * the connection made with it: the access and refresh tokens, encrypted,
      when the access token expires, the handle of the Figma account, who
      connected it and when, and whether Figma refused its refresh token
      (`figma_oauth_needs_reconnect`);
    * a connection being made: the hash of its `state` and, encrypted, what
      the callback checks it against.

  Empty for every existing row: a site with a pasted token keeps using it.
  """

  def up do
    alter table(:mcp_settings, prefix: "public") do
      add_if_not_exists :figma_client_id, :binary
      add_if_not_exists :figma_client_id_hint, :text
      add_if_not_exists :figma_client_secret, :binary
      add_if_not_exists :figma_app_set_at, :utc_datetime_usec

      add_if_not_exists :figma_app_set_by_id,
                        references(:users, on_delete: :nilify_all, prefix: "public")

      add_if_not_exists :figma_oauth_access_token, :binary
      add_if_not_exists :figma_oauth_refresh_token, :binary
      add_if_not_exists :figma_oauth_expires_at, :utc_datetime_usec
      add_if_not_exists :figma_oauth_handle, :text
      add_if_not_exists :figma_oauth_connected_at, :utc_datetime_usec

      add_if_not_exists :figma_oauth_connected_by_id,
                        references(:users, on_delete: :nilify_all, prefix: "public")

      add_if_not_exists :figma_oauth_needs_reconnect, :boolean, default: false, null: false
      add_if_not_exists :figma_oauth_state_hash, :binary
      add_if_not_exists :figma_oauth_pending, :binary
    end
  end

  def down do
    alter table(:mcp_settings, prefix: "public") do
      remove_if_exists :figma_oauth_pending, :binary
      remove_if_exists :figma_oauth_state_hash, :binary
      remove_if_exists :figma_oauth_needs_reconnect, :boolean
      remove_if_exists :figma_oauth_connected_by_id, :bigint
      remove_if_exists :figma_oauth_connected_at, :utc_datetime_usec
      remove_if_exists :figma_oauth_handle, :text
      remove_if_exists :figma_oauth_expires_at, :utc_datetime_usec
      remove_if_exists :figma_oauth_refresh_token, :binary
      remove_if_exists :figma_oauth_access_token, :binary
      remove_if_exists :figma_app_set_by_id, :bigint
      remove_if_exists :figma_app_set_at, :utc_datetime_usec
      remove_if_exists :figma_client_secret, :binary
      remove_if_exists :figma_client_id_hint, :text
      remove_if_exists :figma_client_id, :binary
    end
  end
end
