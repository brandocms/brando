defmodule Brando.Repo.Migrations.Brando250AddSSGContentChanges do
  use Ecto.Migration

  @moduledoc """
  When each environment's content last changed (`ssg_content_changes`, one
  row per environment, `Brando.SSG.ContentChanges`), and when a static build
  started (`ssg_builds.started_at`), so a static site can tell whether its
  content changed after the build it serves. Both live in `public`.

  The table starts empty and a build made before has no `started_at`: such a
  build compares by when it was queued, and the environment's activity log
  covers what was edited before the first change was recorded.
  """

  def up do
    create_if_not_exists table(:ssg_content_changes, primary_key: false, prefix: "public") do
      add :environment_id, references(:environments, on_delete: :delete_all, prefix: "public"),
        primary_key: true

      add :changed_at, :utc_datetime_usec, null: false
    end

    alter table(:ssg_builds, prefix: "public") do
      add_if_not_exists :started_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:ssg_builds, prefix: "public") do
      remove_if_exists :started_at, :utc_datetime_usec
    end

    drop_if_exists table(:ssg_content_changes, prefix: "public")
  end
end
