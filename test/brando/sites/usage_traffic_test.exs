defmodule Brando.Sites.UsageTrafficTest do
  # The counters are one named table per node, so these run alone
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Plug.Conn

  alias Brando.SiteAssetsFixtures
  alias Brando.Sites.Usage
  alias Brando.Sites.Usage.Day
  alias Brando.Sites.Usage.Traffic
  alias Brando.Tenant

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.Cache.clear()

    files = Path.join(System.tmp_dir!(), "brando-usage-traffic-#{System.unique_integer([:positive])}")
    File.mkdir_p!(files)
    put_test_env(:release_static_path, files)

    on_exit(fn ->
      File.rm_rf(files)
      Tenant.Cache.clear()
    end)

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "traffic-acme", "acme.traffic.test")
    {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "traffic-beta", "beta.traffic.test")

    [environment] = acme.environments

    {:ok, _environment} =
      Tenant.Registry.update_environment(environment, %{redirect_hosts: ["www.acme.traffic.test"]}, actor: :system)

    start_supervised!({Traffic, :timer.hours(1)})

    %{acme: acme, beta: beta, files: files}
  end

  defp today, do: Date.utc_today()

  defp request(method \\ :get, host, path, fun) do
    method
    |> Plug.Test.conn("http://#{host}#{path}")
    |> Map.put(:host, host)
    |> Brando.Plug.Usage.call([])
    |> fun.()
  end

  defp traffic(site) do
    case Usage.days(site, today(), 1) do
      [%Day{requests: requests, bytes_sent: bytes}] -> {requests, bytes}
      [] -> {0, 0}
    end
  end

  describe "counting" do
    test "attributes each request to the site whose host it reached, and adds across two flushes", %{
      acme: acme,
      beta: beta
    } do
      request("acme.traffic.test", "/", &send_resp(&1, 200, "hello"))
      request("beta.traffic.test", "/", &send_resp(&1, 200, "hi"))
      :ok = Traffic.flush()

      request("www.acme.traffic.test", "/", &send_resp(&1, 301, ""))
      request("acme.traffic.test", "/missing", &send_resp(&1, 404, "not found"))
      :ok = Traffic.flush()

      assert traffic(acme) == {3, 14}
      assert traffic(beta) == {1, 2}
    end

    test "the admin's host, an unknown host and an inactive site's host count for nobody", %{beta: beta} do
      {:ok, _beta} = Tenant.Registry.update_site(beta, %{status: :suspended})

      request(BrandoAdmin.AdminHost.endpoint_host(), "/admin", &send_resp(&1, 200, "admin"))
      request("nobody.traffic.test", "/", &send_resp(&1, 200, "x"))
      request("beta.traffic.test", "/", &send_resp(&1, 200, "x"))
      :ok = Traffic.flush()

      assert Brando.Repo.all(Day, prefix: "public") == []
    end

    test "counts a body, a full file, a range, HEAD, 304, a redirect and an error by the bytes sent", %{
      acme: acme,
      files: files
    } do
      File.mkdir_p!(Path.join(files, "assets"))
      File.write!(Path.join([files, "assets", "app.js"]), String.duplicate("a", 1_000))
      static = Plug.Static.init(at: "/", from: files, only: ~w(assets))

      # A full file from the release's Plug.Static
      request("acme.traffic.test", "/assets/app.js", &Plug.Static.call(&1, static))
      assert traffic_after_flush(acme) == {1, 1_000}

      # A range of it
      request("acme.traffic.test", "/assets/app.js", fn conn ->
        conn |> put_req_header("range", "bytes=100-199") |> Plug.Static.call(static)
      end)

      assert traffic_after_flush(acme) == {2, 1_100}

      # A file a Brando plug names, as Brando.Plug.Media and the site assets do
      other = Path.join(files, "other.bin")
      File.write!(other, String.duplicate("b", 50))

      request("acme.traffic.test", "/media/other.bin", fn conn ->
        conn |> Brando.Plug.Usage.put_file(other) |> send_file(200, other)
      end)

      assert traffic_after_flush(acme) == {3, 1_150}

      request(:head, "acme.traffic.test", "/", &send_resp(&1, 200, "a body HEAD does not send"))
      request("acme.traffic.test", "/", &send_resp(&1, 304, ""))
      request("acme.traffic.test", "/", &Phoenix.Controller.redirect(&1, to: "/elsewhere"))
      request("acme.traffic.test", "/", &send_resp(&1, 500, "error"))

      redirect_bytes = byte_size(Phoenix.Controller.redirect(Plug.Test.conn(:get, "/"), to: "/elsewhere").resp_body)
      assert traffic_after_flush(acme) == {7, 1_150 + redirect_bytes + 5}
    end

    test "the day is the request's, fixed when it arrives", %{acme: acme} do
      yesterday = Date.add(today(), -1)
      :ok = Traffic.count(acme.id, yesterday, 7)
      request("acme.traffic.test", "/", &send_resp(&1, 200, "x"))
      :ok = Traffic.flush()

      assert [%Day{day: ^yesterday, requests: 1, bytes_sent: 7}, %Day{requests: 1, bytes_sent: 1}] =
               Usage.days(acme, today(), 2)
    end
  end

  defp traffic_after_flush(site) do
    :ok = Traffic.flush()
    traffic(site)
  end

  describe "flushing" do
    test "a failed flush keeps its counts, and requests counted meanwhile, for the next", %{acme: acme} do
      :ok = Traffic.count(acme.id, today(), 10)
      # A key the write cannot take makes it raise before it reaches the
      # database, whose sandbox transaction an error would end
      :ok = Traffic.count("not a site id", today(), 1)

      ExUnit.CaptureLog.capture_log(fn -> :ok = Traffic.flush() end)
      assert traffic(acme) == {0, 0}

      :ets.delete(Traffic, {"not a site id", today()})
      :ok = Traffic.count(acme.id, today(), 5)
      :ok = Traffic.flush()

      assert traffic(acme) == {2, 15}
    end

    test "counts of a deleted site are skipped, and the others written", %{acme: acme, beta: beta} do
      :ok = Traffic.count(beta.id, today(), 4)
      :ok = Traffic.count(acme.id, today(), 1)
      Brando.Repo.delete!(beta)

      :ok = Traffic.flush()

      assert traffic(acme) == {1, 1}
      assert :ets.tab2list(Traffic) == []
    end

    test "the counters are written once more at shutdown", %{acme: acme} do
      :ok = Traffic.count(acme.id, today(), 3)
      :ok = stop_supervised(Traffic)
      assert traffic(acme) == {1, 3}
    end
  end

  test "outside :multi no counter starts and nothing is counted", %{acme: acme} do
    for mode <- [:none, :single] do
      put_test_env(:tenancy_mode, mode)
      assert Traffic.children() == []

      conn = request("acme.traffic.test", "/", &send_resp(&1, 200, "x"))
      assert conn.status == 200
    end

    put_test_env(:tenancy_mode, :multi)
    :ok = Traffic.flush()
    assert traffic(acme) == {0, 0}
    assert Traffic.children() != []
  end
end
