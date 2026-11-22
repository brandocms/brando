defmodule Brando.Repo.Migrations.Brando244AddFragmentAlternates do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `pages_fragments_alternates`: language links
  between fragments (`Brando.Pages.Fragment.Alternate`), as
  `pages_alternates` links pages. Fragments are linked when they are created
  as translations, from the fragment form, or by `mix brando.fragments.pair`
  for fragments that share their keys.

  An installation that runs `brando_93` with this version of Brando already
  has the table from it: Brando's fragments have language links now, and
  `brando_93` creates the table of every Blueprint that has them. This
  creates it where it is missing, with the same columns and constraints, and
  leaves it as it is elsewhere. An environment without fragments is left
  alone.
  """

  def up do
    for prefix <- prefixes(), table?(prefix, "pages_fragments") do
      create_if_not_exists table(:pages_fragments_alternates, prefix: prefix) do
        add :entry_id, references(:pages_fragments, on_delete: :delete_all, prefix: prefix)
        add :linked_entry_id, references(:pages_fragments, on_delete: :delete_all, prefix: prefix)
        timestamps()
      end

      create_if_not_exists unique_index(:pages_fragments_alternates, [:entry_id, :linked_entry_id], prefix: prefix)
    end
  end

  # The table may be `brando_93`'s, and holds links editors made: a rollback
  # leaves it as it is.
  def down, do: :ok

  defp table?(prefix, table) do
    %{rows: [[name]]} = repo().query!("SELECT to_regclass($1)::text", [~s("#{prefix}".#{table})])
    not is_nil(name)
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
