defmodule Brando.Repo.Migrations.Brando216AddProposalsToActivityEvents do
  use Ecto.Migration

  @moduledoc """
  In every site environment, two columns on the activity log
  (`Brando.Activity.Event`) for changes an agent prepared:

    * `proposal_id` is the content proposal a change came from
      (`Brando.Content.Proposals`), from the Assistant or a tool connected
      over MCP.
    * `approver_id` is the user who approved and applied it, apart from the
      agent that prepared it (the event's `source`).

  Events recorded before this ran have no proposal. Those an agent made
  (`source` `assistant` or `mcp`, not a tool's own call) were applied by
  their user, who becomes their approver; the rest stay as they were,
  people's changes by default.

  Users live in `public`, so the foreign key names that schema.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:activity_events, prefix: prefix) do
        add :proposal_id, :uuid
        add :approver_id, references(:users, prefix: "public", on_delete: :nilify_all)
      end

      create index(:activity_events, [:proposal_id], prefix: prefix)

      execute """
      UPDATE "#{prefix}".activity_events SET approver_id = user_id
      WHERE source IN ('assistant', 'mcp') AND action <> 'tool_called' AND user_id IS NOT NULL
      """
    end
  end

  def down do
    for prefix <- prefixes() do
      drop index(:activity_events, [:proposal_id], prefix: prefix)

      alter table(:activity_events, prefix: prefix) do
        remove :approver_id
        remove :proposal_id
      end
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
