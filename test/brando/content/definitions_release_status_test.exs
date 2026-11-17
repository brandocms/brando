defmodule Brando.Content.DefinitionsReleaseStatusTest do
  # The background plan of the release's definitions, its cache, and what
  # the admin shows from it
  use Brando.LiveCase, async: false

  alias Brando.Content.{Definitions, Module}
  alias Brando.Content.Definitions.{Release, ReleaseStatus}
  alias Brando.{Factory, Repo}
  alias Ecto.Changeset

  setup %{current_user: user} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    path = Path.join(System.tmp_dir!(), "brando-release-status-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    source = File.read!("test/fixtures/definitions/hero.exs.txt")
    File.write!(Path.join(path, "hero.exs"), source)
    put_test_env(Definitions, release_path: path)
    ReleaseStatus.clear()

    on_exit(fn ->
      ReleaseStatus.clear()
      File.rm_rf!(path)
    end)

    %{user: user, path: path, source: source}
  end

  defp write!(c, from, to), do: File.write!(Path.join(c.path, "hero.exs"), String.replace(c.source, from, to))

  defp hero, do: Repo.get_by!(Module, uid: "hero-test")

  # Retried until `fun` holds: the server plans in its own process
  defp eventually(fun, tries \\ 100) do
    if fun.() || tries == 0 do
      assert fun.()
    else
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  describe "the cached plan" do
    test "is planned again only when the release or the database changed", c do
      assert ReleaseStatus.summary() == nil
      assert ReleaseStatus.refresh(nil, version: "1.0.0") == :planned
      assert %{pending: 1, version: "1.0.0"} = ReleaseStatus.summary()

      assert ReleaseStatus.refresh(nil, version: "1.0.0") == :unchanged

      {:ok, _} = Release.apply(:all, user: c.user.id, version: "1.0.0")
      assert ReleaseStatus.refresh(nil, version: "1.0.0") == :planned
      assert %{pending: 0, states: states} = ReleaseStatus.summary()
      assert states == %{}

      # A save in the admin changes the database's digest
      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
      assert ReleaseStatus.refresh(nil) == :planned
      assert ReleaseStatus.state("hero-test") == :changed_in_admin
      assert %{pending: 0} = ReleaseStatus.summary()

      # A new release file changes the release's
      write!(c, ~s(class "hero"), ~s(class "file-class"))
      assert ReleaseStatus.refresh(nil) == :planned
      assert ReleaseStatus.state("hero-test") == :changed_in_both
      assert %{pending: 1} = ReleaseStatus.summary()
    end

    test "says nothing without release_path, or a directory", c do
      put_test_env(Definitions, [])
      assert ReleaseStatus.refresh(nil) == :off
      assert ReleaseStatus.summary() == nil

      put_test_env(Definitions, release_path: Path.join(c.path, "missing"))
      assert ReleaseStatus.refresh(nil) == :off
      assert ReleaseStatus.summary() == nil
    end

    test "a release it can't plan shows no changes, and doesn't crash", c do
      File.write!(Path.join(c.path, "hero.exs"), "defmodule Broken do\n  uid ")

      previous = Logger.level()
      Logger.configure(level: :warning)
      on_exit(fn -> Logger.configure(level: previous) end)
      log = ExUnit.CaptureLog.capture_log(fn -> assert ReleaseStatus.refresh(nil) == :off end)
      assert log =~ "Could not plan the release's module definitions"

      assert ReleaseStatus.summary() == nil
    end

    test "the server plans after boot, in its own process, and again when definitions change", c do
      # It plans once it has the test's connection
      pid = start_supervised!({ReleaseStatus, delay: 50, version: "1.0.0"})
      Ecto.Adapters.SQL.Sandbox.allow(Repo.repo(), self(), pid)

      eventually(fn -> match?(%{pending: 1}, ReleaseStatus.summary()) end)

      # The apply announces itself; the server plans again
      {:ok, _} = Release.apply(:all, user: c.user.id, version: "1.0.0")
      eventually(fn -> match?(%{pending: 0}, ReleaseStatus.summary()) end)

      {:ok, _} =
        Brando.Content.update_module(hero().id, %{class: "admin-class"}, c.user)

      eventually(fn -> ReleaseStatus.state("hero-test") == :changed_in_admin end)
    end

    test "only starts where it serves, with release_path configured" do
      put_test_env(Definitions, [])
      assert ReleaseStatus.children() == []

      # The test endpoint doesn't serve, and the repo is the sandbox
      put_test_env(Definitions, release_path: "priv/modules")
      assert ReleaseStatus.children() == []
    end
  end

  describe "the admin" do
    test "superusers see the changes waiting on the dashboard; others don't", c do
      ReleaseStatus.refresh(nil, version: "2.0.0")

      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: c.user)
      assert html =~ "dashboard-release-modules"
      assert html =~ "This release has 1 module change that isn&#39;t applied yet"
      assert html =~ "Release 2.0.0"
      assert html =~ ~s(href="/admin/config/content/modules")
      assert html =~ "Brando.Content.Definitions.Release.status()"

      admin = Factory.insert(:random_user, role: :admin)
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: admin)
      refute html =~ "dashboard-release-modules"
    end

    test "no notice when nothing waits", c do
      {:ok, _} = Release.apply(:all, user: c.user.id)
      ReleaseStatus.refresh(nil)

      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: c.user)
      refute html =~ "dashboard-release-modules"
    end

    test "Block modules marks the modules the release and the admin changed", %{conn: conn} = c do
      {:ok, _} = Release.apply(:all, user: c.user.id)
      write!(c, ~s(class "hero"), ~s(class "file-class"))
      ReleaseStatus.refresh(nil)

      {:ok, _view, html} = live(conn, "/admin/config/content/modules")
      assert html =~ ~s(data-source="release")
      assert html =~ ~s(data-state="changed_in_release")
      assert html =~ "Changed in this release"

      hero() |> Changeset.change(class: "admin-class") |> Repo.update!()
      ReleaseStatus.refresh(nil)
      {:ok, _view, html} = live(conn, "/admin/config/content/modules")
      assert html =~ "Changed here and in this release"
    end
  end
end
