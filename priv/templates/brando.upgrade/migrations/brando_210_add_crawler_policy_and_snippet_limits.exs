defmodule Brando.Repo.Migrations.Brando210AddCrawlerPolicyAndSnippetLimits do
  use Ecto.Migration

  @moduledoc """
  In every site environment:

    * `sites_seos.crawler_policy` holds the AI crawler policy that
      `Brando.SEO.Robots` writes into robots.txt. Empty means every crawler
      is allowed and nothing is written, as before.
    * `Brando.Trait.Meta` adds `meta_nosnippet` and `meta_max_snippet`, here
      added to Brando's own table with the trait; application blueprints get
      them planned by `mix brando.gen.blueprint_migration --all`.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:sites_seos, prefix: prefix) do
        add :crawler_policy, :map
      end

      alter table(:pages, prefix: prefix) do
        add :meta_nosnippet, :boolean, default: false
        add :meta_max_snippet, :integer
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:pages, prefix: prefix) do
        remove :meta_max_snippet
        remove :meta_nosnippet
      end

      alter table(:sites_seos, prefix: prefix) do
        remove :crawler_policy
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
