defmodule Brando.Repo.Migrations.Brando232AddFigmaTokenToMCPSettings do
  use Ecto.Migration

  @moduledoc """
  `mcp_settings.figma_token`: the Figma access token connected AI tools use
  to read a Figma frame and import its images (`Brando.Figma`), one per site
  environment, encrypted with `Brando.Crypto`. `figma_token_hint` keeps its
  last four characters to show in the admin, and `figma_token_set_at` and
  `figma_token_set_by_id` when and by whom it was added. Empty for every
  existing row.
  """

  def up do
    alter table(:mcp_settings, prefix: "public") do
      add_if_not_exists :figma_token, :binary
      add_if_not_exists :figma_token_hint, :text
      add_if_not_exists :figma_token_set_at, :utc_datetime_usec

      add_if_not_exists :figma_token_set_by_id,
                        references(:users, on_delete: :nilify_all, prefix: "public")
    end
  end

  def down do
    alter table(:mcp_settings, prefix: "public") do
      remove_if_exists :figma_token_set_by_id, :bigint
      remove_if_exists :figma_token_set_at, :utc_datetime_usec
      remove_if_exists :figma_token_hint, :text
      remove_if_exists :figma_token, :binary
    end
  end
end
