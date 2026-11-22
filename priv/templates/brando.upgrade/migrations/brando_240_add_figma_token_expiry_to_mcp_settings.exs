defmodule Brando.Repo.Migrations.Brando240AddFigmaTokenExpiryToMCPSettings do
  use Ecto.Migration

  @moduledoc """
  `mcp_settings.figma_token_expires_on`: the expiry date an administrator
  gives when saving the Figma access token (Figma's API does not tell it),
  for the admin and the Figma tools to warn before it lapses. Empty for every
  existing row: a token saved before has no recorded expiry.
  """

  def up do
    alter table(:mcp_settings, prefix: "public") do
      add_if_not_exists :figma_token_expires_on, :date
    end
  end

  def down do
    alter table(:mcp_settings, prefix: "public") do
      remove_if_exists :figma_token_expires_on, :date
    end
  end
end
