defmodule BrandoIntegration.Repo.Migrations.AddFigmaTokenExpiryToMCPSettings do
  use Ecto.Migration

  # Mirrors the brando_240 upgrade migration for the test schema.
  @moduledoc """
  `mcp_settings.figma_token_expires_on`: the expiry date given when the
  Figma access token was saved.
  """

  def change do
    alter table(:mcp_settings) do
      add :figma_token_expires_on, :date
    end
  end
end
