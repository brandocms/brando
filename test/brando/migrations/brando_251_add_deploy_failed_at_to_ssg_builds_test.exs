defmodule Brando.Migrations.Brando251AddDeployFailedAtToSSGBuildsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [column_set: 2, columns: 2, down: 2, query!: 1, up: 1]

  @file_name "brando_251_add_deploy_failed_at_to_ssg_builds.exs"

  test "adds when a build's deploy was given up, in public, and rolls back" do
    expected = column_set("public", %{"ssg_builds" => ["deploy_failed_at"]})
    query!("ALTER TABLE public.ssg_builds DROP COLUMN deploy_failed_at")

    version = up(@file_name)

    assert column_set("public", %{"ssg_builds" => ["deploy_failed_at"]}) == expected
    assert :deploy_failed_at in Brando.SSG.Build.__schema__(:fields)

    down(@file_name, version)

    refute "deploy_failed_at" in columns("public", "ssg_builds")
  end
end
