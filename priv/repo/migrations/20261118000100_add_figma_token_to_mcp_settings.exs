defmodule BrandoIntegration.Repo.Migrations.AddFigmaTokenToMCPSettings do
  use Ecto.Migration

  # Mirrors the brando_232 upgrade migration for the test schema.
  @moduledoc """
  `mcp_settings.figma_token`: the encrypted Figma access token connected AI
  tools import from (`Brando.Figma`), its last four characters, and when and
  by whom it was added.
  """

  def change do
    alter table(:mcp_settings) do
      add :figma_token, :binary
      add :figma_token_hint, :text
      add :figma_token_set_at, :utc_datetime_usec
      add :figma_token_set_by_id, references(:users, on_delete: :nilify_all)
    end
  end
end
