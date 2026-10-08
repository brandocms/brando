defmodule Brando.Repo.Migrations.Brando214AddUnpublishAt do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `Brando.Trait.ScheduledPublishing` adds
  `unpublish_at` beside `publish_at`: when the entry expires and is
  deactivated. Here it is added to Brando's own tables with the trait, pages
  and fragments; application blueprints get it planned by
  `mix brando.gen.blueprint_migration`. Existing entries have no expiry.
  """

  @tables [:pages, :pages_fragments]

  def up do
    for prefix <- prefixes(), table <- @tables do
      alter table(table, prefix: prefix) do
        add :unpublish_at, :utc_datetime
      end

      create index(table, [:unpublish_at], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes(), table <- @tables do
      drop index(table, [:unpublish_at], prefix: prefix)

      alter table(table, prefix: prefix) do
        remove :unpublish_at
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
