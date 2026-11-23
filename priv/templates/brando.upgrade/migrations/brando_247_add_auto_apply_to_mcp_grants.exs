defmodule Brando.Repo.Migrations.Brando247AddAutoApplyToMCPGrants do
  use Ecto.Migration

  @moduledoc """
  A connection may be let to apply some proposals without review
  (`Brando.MCP.Grant`):

    * `mcp_grants.auto_apply` — `"none"`, or `"unpublished_translations"`:
      proposals that only create unpublished translations are applied as
      the connection stores them. `"none"` for every existing connection.
    * `mcp_grants.auto_apply_set_by_id` and `auto_apply_set_at` — who last
      changed it, and when.
    * `content_proposals.auto_applied_grant_id` — the connection a proposal
      was applied automatically under; and `auto_apply_reason`, why one that
      asked for it was left for review instead. The connection's id is kept
      without a foreign key, so the record outlives the connection.

  These tables live in the `public` schema only.
  """

  def up do
    alter table(:mcp_grants, prefix: "public") do
      add_if_not_exists :auto_apply, :text, null: false, default: "none"
      add_if_not_exists :auto_apply_set_by_id, references(:users, on_delete: :nilify_all, prefix: "public")
      add_if_not_exists :auto_apply_set_at, :utc_datetime_usec
    end

    alter table(:content_proposals, prefix: "public") do
      add_if_not_exists :auto_applied_grant_id, :bigint
      add_if_not_exists :auto_apply_reason, :text
    end
  end

  def down do
    alter table(:content_proposals, prefix: "public") do
      remove_if_exists :auto_apply_reason, :text
      remove_if_exists :auto_applied_grant_id, :bigint
    end

    alter table(:mcp_grants, prefix: "public") do
      remove_if_exists :auto_apply_set_at, :utc_datetime_usec
      remove_if_exists :auto_apply_set_by_id, :bigint
      remove_if_exists :auto_apply, :text
    end
  end
end
