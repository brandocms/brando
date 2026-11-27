defmodule Brando.Migrations.Brando254ClearVideoPreloadFalseTest do
  # Runs the upgrade template inside the sandbox transaction, over videos
  # whose `preload = false` was stored before lazy became the default (#4004).
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_254_clear_video_preload_false.exs"
  @tenant "tenant_acme_staging"
  @sibling "tenant_acme_preview"

  defp video!(prefix, preload) do
    [[id]] =
      rows(
        ~s{INSERT INTO "#{prefix}".videos (type, preload, inserted_at, updated_at) VALUES ('upload', $1, now(), now()) RETURNING id},
        [preload]
      )

    id
  end

  defp preload(prefix, id), do: rows(~s(SELECT preload FROM "#{prefix}".videos WHERE id = $1), [id])

  defp videos!(prefix), do: Map.new([false, true, nil], &{&1, video!(prefix, &1)})

  defp assert_cleared(prefix, ids) do
    assert preload(prefix, ids[false]) == [[nil]]
    assert preload(prefix, ids[true]) == [[true]]
    assert preload(prefix, ids[nil]) == [[nil]]
  end

  test "clears false in public and every environment, and leaves true and nil alone" do
    public = videos!("public")
    create_environment(@tenant, ["videos"])
    tenant = videos!(@tenant)
    # An environment without the table
    create_environment(@sibling)

    version = up(@template)

    assert_cleared("public", public)
    assert_cleared(@tenant, tenant)

    # Nothing to restore: a cleared value is any other nil
    down(@template, version)
    assert preload("public", public[false]) == [[nil]]
  end

  test "a run for one environment leaves the others alone" do
    public = videos!("public")
    create_environment(@tenant, ["videos"])
    create_environment(@sibling, ["videos"])
    tenant = videos!(@tenant)
    sibling = videos!(@sibling)

    up(@template, prefix: @tenant)

    assert_cleared(@tenant, tenant)
    assert preload(@sibling, sibling[false]) == [[false]]
    assert preload("public", public[false]) == [[false]]
  end
end
