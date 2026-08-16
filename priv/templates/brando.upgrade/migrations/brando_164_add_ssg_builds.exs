defmodule Brando.Repo.Migrations.Brando164AddSsgBuilds do
  use Ecto.Migration

  def change do
    create table(:ssg_builds, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false

      add :environment_id, references(:environments, prefix: "public", on_delete: :nilify_all)
      add :environment_name, :text, null: false
      add :environment_key, :text, null: false

      add :asset_set_id, references(:site_asset_sets, prefix: "public", on_delete: :nilify_all)
      add :creator_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :version, :text, null: false
      add :build_number, :integer, null: false
      add :status, :text, null: false, default: "queued"
      add :build_path, :text, null: false
      add :build_log, :text, null: false, default: ""
      add :note, :text
      add :file_count, :integer, null: false, default: 0
      add :total_size, :bigint, null: false, default: 0
      add :url_count, :integer, null: false, default: 0
      add :processed_urls, :integer, null: false, default: 0
      add :failed_urls, {:array, :text}, null: false, default: []
      add :auto_deploy, :boolean, null: false, default: false
      add :deploy_config, :map, null: false, default: %{}
      add :preview_token, :text, null: false
      add :preview_expires_at, :utc_datetime_usec, null: false
      add :scheduled_at, :utc_datetime_usec
      add :built_at, :utc_datetime_usec
      add :deployed_at, :utc_datetime_usec
      add :pruned_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ssg_builds, [:site_id, :build_number], prefix: "public")
    create unique_index(:ssg_builds, [:preview_token], prefix: "public")
    create index(:ssg_builds, [:site_id, :inserted_at], prefix: "public")
    create index(:ssg_builds, [:site_id, :status], prefix: "public")
    create index(:ssg_builds, [:scheduled_at], prefix: "public")
  end
end
