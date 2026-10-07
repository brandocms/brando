defmodule BrandoIntegration.Repo.Migrations.AddOriginToContentProposals do
  use Ecto.Migration

  # Mirrors the brando_207 upgrade migration for the test schema.
  @moduledoc """
  Where a content proposal came from: the admin's Assistant or a tool
  connected over MCP (`origin`), and that tool's name when known (`client`).
  """

  def up do
    alter table(:content_proposals, prefix: "public") do
      add :origin, :text
      add :client, :text
    end

    execute "UPDATE public.content_proposals SET origin = 'assistant' WHERE conversation_id IS NOT NULL"
  end

  def down do
    alter table(:content_proposals, prefix: "public") do
      remove :origin
      remove :client
    end
  end
end
