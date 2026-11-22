defmodule Brando.Sites.UsageTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [copy_schema: 2, provision: 1, table?: 2]

  alias Brando.Sites.Usage
  alias Brando.Sites.Usage.Day
  alias Brando.SiteAssetsFixtures
  alias Brando.Tenant

  @today ~D[2026-11-22]

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.Cache.clear()
    on_exit(fn -> Tenant.Cache.clear() end)

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "usage-acme", "acme.usage.test")
    {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "usage-beta", "beta.usage.test")
    %{acme: acme, beta: beta}
  end

  defp measurement(media), do: %{media_bytes: media, builds_bytes: 10, databases: [db("production", 100)]}
  defp db(environment, bytes), do: %{"schema" => "s", "environment" => environment, "archive" => false, "bytes" => bytes}

  describe "the two writers" do
    test "a flush adds to the counters and leaves a measurement alone", %{acme: acme} do
      :ok = Usage.put_measurement(acme.id, @today, measurement(1_000))
      [%Day{measured_at: measured_at}] = Usage.days(acme, @today)

      :ok = Usage.add_traffic([{acme.id, @today, 3, 300}])
      :ok = Usage.add_traffic([{acme.id, @today, 2, 50}])

      assert [%Day{requests: 5, bytes_sent: 350, media_bytes: 1_000, measured_at: ^measured_at} = day] =
               Usage.days(acme, @today)

      assert Day.storage_bytes(day) == 1_110
    end

    test "a measurement sets the sizes and leaves the counters alone", %{acme: acme} do
      :ok = Usage.add_traffic([{acme.id, @today, 3, 300}])
      :ok = Usage.put_measurement(acme.id, @today, measurement(1_000))
      :ok = Usage.put_measurement(acme.id, @today, measurement(2_000))

      assert [%Day{requests: 3, bytes_sent: 300, media_bytes: 2_000}] = Usage.days(acme, @today)
    end

    test "a day with traffic and no measurement has unknown storage, not zero", %{acme: acme} do
      :ok = Usage.add_traffic([{acme.id, @today, 1, 10}])

      assert [day] = Usage.days(acme, @today)
      refute Day.measured?(day)
      assert Day.storage_bytes(day) == nil
    end
  end

  test "counts for a deleted site are dropped without failing the others", %{acme: acme, beta: beta} do
    Brando.Repo.delete!(beta)

    :ok = Usage.add_traffic([{beta.id, @today, 4, 40}, {acme.id, @today, 1, 10}])

    assert [%Day{requests: 1}] = Usage.days(acme, @today)
    assert Brando.Repo.all(Day, prefix: "public") |> Enum.map(& &1.site_id) == [acme.id]
  end

  test "deleting a site deletes its rows", %{acme: acme} do
    :ok = Usage.add_traffic([{acme.id, @today, 1, 10}])
    Brando.Repo.delete!(acme)
    assert Brando.Repo.all(Day, prefix: "public") == []
  end

  test "overview sums the traffic of the period and takes the latest measurement", %{acme: acme, beta: beta} do
    :ok = Usage.put_measurement(acme.id, Date.add(@today, -3), measurement(500))
    :ok = Usage.put_measurement(acme.id, Date.add(@today, -1), measurement(700))
    :ok = Usage.add_traffic([{acme.id, @today, 2, 20}, {acme.id, Date.add(@today, -29), 3, 30}])
    # Outside the 30 days
    :ok = Usage.add_traffic([{acme.id, Date.add(@today, -30), 100, 1_000}, {beta.id, @today, 1, 1}])

    overview = Usage.overview(@today)

    assert %{requests: 5, bytes_sent: 50, measured: %Day{media_bytes: 700}} = overview[acme.id]
    assert %{requests: 1, measured: nil} = overview[beta.id]
  end

  # Reached through a tenant prefix too: the table is shared, next to the sites
  test "is read and written in public while a tenant prefix is active", %{acme: acme} do
    Tenant.with_prefix(Tenant.prefix(acme.key, "production"), fn ->
      :ok = Usage.add_traffic([{acme.id, @today, 1, 10}])
      :ok = Usage.put_measurement(acme.id, @today, measurement(1))
      assert [%Day{requests: 1, media_bytes: 1}] = Usage.days(acme, @today)
    end)

    assert [%Day{requests: 1}] = Usage.days(acme, @today)
  end

  test "an environment provisioned or copied after two sites have usage gets no copy of it", %{
    acme: acme,
    beta: beta
  } do
    :ok = Usage.add_traffic([{acme.id, @today, 1, 10}, {beta.id, @today, 2, 20}])
    assert Tenant.SharedTables.member?("sites_usage_days")

    provision("tenant_usage-acme_staging")
    copy_schema("tenant_usage-acme_staging", "tenant_usage-acme_preview")

    refute table?("tenant_usage-acme_staging", "sites_usage_days")
    refute table?("tenant_usage-acme_preview", "sites_usage_days")

    assert Brando.Repo.all(Day, prefix: "public") |> Enum.map(&{&1.site_id, &1.requests}) |> Enum.sort() ==
             Enum.sort([{acme.id, 1}, {beta.id, 2}])
  end
end
