defmodule BrandoAdmin.Sites.SiteUsageLiveTest do
  # The Usage section and the usage line in the site list on the Sites
  # screen, which only a superuser sees
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Sites.Usage
  alias Brando.Sites.Usage.Day
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  setup %{current_user: user} do
    media = Path.join(System.tmp_dir!(), "brando-usage-live-#{System.unique_integer([:positive])}")
    File.mkdir_p!(media)
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:media_path, media)
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(media)
      Brando.Tenant.Cache.clear()
    end)

    Brando.endpoint().subscribe("user:#{user.id}")

    sites =
      for {name, key} <- [{"Acme", "acme"}, {"Beta", "beta"}, {"Gamma", "gamma"}], into: %{} do
        {:ok, site} =
          Registry.create_site(%{
            name: name,
            key: key,
            languages: ["en"],
            default_language: "en",
            status: :active,
            delivery_mode: :dynamic
          })

        {String.to_atom(key), Registry.get_site(site.id)}
      end

    today = Date.utc_today()

    # Acme: 30 days of rows, each measured, growing by a kilobyte a day
    for offset <- 0..29 do
      day = Date.add(today, -offset)
      :ok = Usage.add_traffic([{sites.acme.id, day, 100 + offset, 1_000}])

      :ok =
        Usage.put_measurement(sites.acme.id, day, %{
          media_bytes: 1_048_576 - offset * 1_024,
          builds_bytes: 0,
          databases: [
            %{"schema" => "tenant_acme_production", "environment" => "production", "archive" => false, "bytes" => 2_048},
            %{
              "schema" => "tenant_acme_production_archive_20261101120000",
              "environment" => "production",
              "archive" => true,
              "bytes" => 1_024
            }
          ]
        })
    end

    # Gamma: traffic and no measurement
    :ok = Usage.add_traffic([{sites.gamma.id, today, 7, 70}])

    Map.put(sites, :today, today)
  end

  test "a superuser sees each site's storage and requests in the list, and a site's breakdown and trend", %{
    conn: conn,
    acme: acme
  } do
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    # 1 MB of media and 3 KB of databases; 30 days of 100 to 129 requests
    assert has_element?(view, "#site-list-usage-#{acme.id}", "1.0 MB")
    assert has_element?(view, "#site-list-usage-#{acme.id}", "3 435")

    assert has_element?(view, "#usage-storage-facts-#{acme.id}", "1.0 MB")
    assert has_element?(view, "#usage-db-#{acme.id}-tenant_acme_production", "2.0 KB")
    assert has_element?(view, "#usage-db-#{acme.id}-tenant_acme_production_archive_20261101120000", "1.0 KB")
    assert has_element?(view, "#usage-change-#{acme.id}", "+29.0 KB")
    assert has_element?(view, "#usage-traffic-#{acme.id}", "3 435")
    assert has_element?(view, "#usage-traffic-#{acme.id}", "29.3 KB")

    assert view
           |> element("#usage-traffic-#{acme.id} svg")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("rect")
           |> length() == 30

    assert has_element?(view, "#usage-installation-#{acme.id}", "1.0 MB")
  end

  test "a site with no rows, and one with traffic and no measurement, show their storage as unknown", %{
    conn: conn,
    beta: beta,
    gamma: gamma
  } do
    {:ok, view, _html} = live(conn, "/admin/sites?site=beta")

    assert has_element?(view, "#usage-storage-#{beta.id}")
    refute has_element?(view, "#usage-storage-facts-#{beta.id}")
    assert has_element?(view, "#usage-traffic-#{beta.id}")

    view |> element("#site-list-#{gamma.id}") |> render_click()

    refute has_element?(view, "#usage-storage-facts-#{gamma.id}")
    refute has_element?(view, "#usage-change-#{gamma.id}")
    assert has_element?(view, "#usage-traffic-#{gamma.id}", "70 B")
  end

  test "Measure now measures the site, and the screen shows it when it lands", %{conn: conn, beta: beta, today: today} do
    File.mkdir_p!(Storage.media_root(beta))
    File.write!(Path.join(Storage.media_root(beta), "a.jpg"), String.duplicate("x", 2_048))

    {:ok, view, _html} = live(conn, "/admin/sites?site=beta")
    refute has_element?(view, "#usage-storage-facts-#{beta.id}")

    view |> element("#measure-usage-#{beta.id}") |> render_click()

    assert [%Day{media_bytes: 2_048, day: ^today}] = Usage.days(beta, today)
    assert has_element?(view, "#usage-storage-facts-#{beta.id}", "2.0 KB")
    assert has_element?(view, "#site-list-usage-#{beta.id}", "2.0 KB")
  end

  test "the free space fills in after the first render, and usage rows load only when the selection or a measurement changes them",
       %{conn: conn, acme: acme, beta: beta} do
    test_pid = self()
    handler = "usage-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, %{source: source}, _config ->
        if source == "sites_usage_days", do: send(test_pid, :usage_query)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")
    render_async(view)
    assert has_element?(view, "#usage-free-#{acme.id}")
    refute has_element?(view, "#usage-free-#{acme.id}", "…")
    flush_usage_queries()

    # Selecting another site reads that site's days, and nothing else
    view |> element("#site-list-#{beta.id}") |> render_click()
    assert usage_queries() == 1

    view |> render_hook("refresh", %{})
    assert usage_queries() == 0

    # A measurement of a site not selected: the list's figures only
    send(view.pid, {:site_usage_measured, acme.id})
    render(view)
    assert usage_queries() == 2

    send(view.pid, {:site_usage_measured, beta.id})
    render(view)
    assert usage_queries() == 3
  end

  defp flush_usage_queries do
    receive do
      :usage_query -> flush_usage_queries()
    after
      0 -> :ok
    end
  end

  defp usage_queries(count \\ 0) do
    receive do
      :usage_query -> usage_queries(count + 1)
    after
      0 -> count
    end
  end

  test "before the usage table's migration has run, the screen opens and says so", %{conn: conn, acme: acme} do
    Brando.Repo.repo().query!("DROP TABLE public.sites_usage_days")

    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    assert has_element?(view, "#site-#{acme.id}")
    assert has_element?(view, "#usage-missing-#{acme.id}")
    refute has_element?(view, "#usage-storage-#{acme.id}")
    refute has_element?(view, ".site-list-usage")

    view |> element("#site-list-#{acme.id}") |> render_click()
    assert has_element?(view, "#usage-missing-#{acme.id}")
  end

  test "a message the screen does not handle is ignored", %{conn: conn, acme: acme} do
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")
    send(view.pid, {:something_else, 1})
    assert has_element?(view, "#site-#{acme.id}")
  end

  test "a static site published to another host says what the figures are", %{conn: conn, acme: acme} do
    Brando.Repo.update_all(
      from(site in Brando.Sites.Site, where: site.id == ^acme.id),
      [
        set: [
          delivery_mode: :static,
          deploy_config: %Brando.Sites.DeployConfig{strategy: :rsync, target: "deploy@static.test:/srv/acme"}
        ]
      ],
      prefix: "public"
    )

    Brando.Tenant.Cache.warm()
    {:ok, view, _html} = live(conn, "/admin/sites?site=acme")

    assert has_element?(view, "#usage-elsewhere-#{acme.id}", "deploy@static.test:/srv/acme")
  end

  test "in groups mode, a user who may read Sites but is no superuser sees none of it and cannot measure", %{
    current_user: owner,
    acme: acme,
    beta: beta,
    today: today
  } do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()

    user = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    scope = Brando.Authorization.Scope.installation(owner)

    {:ok, group} =
      Brando.Authorization.Groups.create(scope, %{name: "Site readers"}, [
        "brando.admin.access",
        "brando.sites.read",
        "brando.sites.update"
      ])

    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, user.id)
    Brando.endpoint().subscribe("user:#{user.id}")
    conn = log_in_user(Phoenix.ConnTest.build_conn(), user)

    # The first render
    {:ok, view, html} = live(conn, "/admin/sites?site=acme")
    assert has_element?(view, "#site-#{acme.id}")
    refute has_element?(view, "#usage-site-#{acme.id}")
    refute has_element?(view, "#site-list-usage-#{acme.id}")
    refute html =~ "1.0 MB"

    # Selecting another site
    view |> element("#site-list-#{beta.id}") |> render_click()
    refute has_element?(view, "#usage-site-#{beta.id}")

    # A measurement landing
    send(view.pid, {:site_usage_measured, beta.id})
    refute has_element?(view, "#usage-site-#{beta.id}")
    refute has_element?(view, ".site-list-usage")

    # Measure now, sent directly
    render_click(view, "measure_usage", %{"id" => to_string(beta.id)})

    assert_receive %Phoenix.Socket.Broadcast{
      event: "toast",
      payload: %{payload: "You do not have permission for this action."}
    }

    assert Usage.days(beta, today) == []
  end
end
