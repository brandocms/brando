defmodule Brando.Repo.Migrations.Brando201AddSeoBasics do
  use Ecto.Migration

  @moduledoc """
  `Brando.Trait.Meta` adds `meta_canonical_url`, which overrides the page's
  canonical URL. This adds it to Brando's own table with the trait; application
  blueprints get it planned by `mix brando.gen.blueprint_migration`.
  """

  def change do
    alter table(:pages) do
      add :meta_canonical_url, :text
    end
  end
end
