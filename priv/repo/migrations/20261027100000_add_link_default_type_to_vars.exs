defmodule BrandoIntegration.Repo.Migrations.AddLinkDefaultTypeToVars do
  use Ecto.Migration

  # Mirrors the brando_224 upgrade migration for the test schema.
  @moduledoc """
  `content_vars.link_default_type`: the tab an empty link var's dialog opens
  on (`Brando.Content.Var.FollowLinkDefault`).
  """

  def change do
    alter table(:content_vars) do
      add :link_default_type, :string, default: "url"
    end
  end
end
