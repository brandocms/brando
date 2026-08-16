defmodule Brando.Environments.OperationLogTest do
  use ExUnit.Case, async: true

  alias Brando.Environments.OperationLog

  test "the operation log is permanently public" do
    assert OperationLog.__schema__(:prefix) == "public"
  end

  test "accepts lifecycle audit metadata" do
    changeset =
      OperationLog.changeset(%{
        site_id: 1,
        source_environment_id: 2,
        target_environment_id: 3,
        creator_id: 4,
        operation: :copy,
        archive_schema: "tenant_acme_staging_archive_20260816120000",
        note: "Release copy"
      })

    assert changeset.valid?
  end
end
