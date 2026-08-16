defmodule Brando.Repo.Migrations.AddTenantInfrastructure do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_158_*`.
  """

  def change do
    create table(:sites, prefix: "public") do
      add :name, :text, null: false
      add :key, :text, null: false
      add :languages, {:array, :text}, null: false
      add :default_language, :text, null: false
      add :status, :text, null: false, default: "active"
      add :delivery_mode, :text, null: false, default: "dynamic"
      add :deploy_config, :jsonb, null: false, default: fragment("'{}'::jsonb")
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sites, [:key], prefix: "public")

    create constraint(:sites, :sites_key_format,
             prefix: "public",
             check: "key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'"
           )

    create constraint(:sites, :sites_languages_not_empty,
             prefix: "public",
             check: "cardinality(languages) > 0"
           )

    create constraint(:sites, :sites_default_language_in_languages,
             prefix: "public",
             check: "default_language = ANY(languages)"
           )

    create table(:environments, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :key, :text, null: false
      add :live, :boolean, null: false, default: false
      add :domain, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:environments, [:site_id, :key], prefix: "public")
    create unique_index(:environments, [:domain], prefix: "public")

    create unique_index(:environments, [:site_id],
             prefix: "public",
             name: :environments_one_live_per_site_index,
             where: "live = true"
           )

    create constraint(:environments, :environments_key_format,
             prefix: "public",
             check: "key ~ '^[a-z0-9]+(-[a-z0-9]+)*$'"
           )
  end
end
