defmodule Brando.Repo.Migrations.Brando251AddDeployFailedAtToSSGBuilds do
  use Ecto.Migration

  @moduledoc """
  When a static build's deploy was given up (`ssg_builds.deploy_failed_at`),
  cleared when a deploy of the build starts again. A build whose deploy
  failed stays ready, so the admin's Publish button
  (`Brando.SSG.Publishing`) reads the failure here rather than in the log.
  In `public`; builds made before have none.
  """

  def up do
    alter table(:ssg_builds, prefix: "public") do
      add_if_not_exists :deploy_failed_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:ssg_builds, prefix: "public") do
      remove_if_exists :deploy_failed_at, :utc_datetime_usec
    end
  end
end
