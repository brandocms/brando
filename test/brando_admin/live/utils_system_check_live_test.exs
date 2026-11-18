defmodule BrandoAdmin.UtilsSystemCheckLiveTest do
  use Brando.LiveCase

  alias Brando.DoctorFixtures.{Healthy, Warns}

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  test "loads the checks after the page and shows each with its status and fix", %{conn: conn} do
    put_test_env(Brando.Doctor, checks: [Healthy, Warns], skip: Brando.Doctor.default_checks())

    {:ok, view, html} = live(conn, "/admin/config/utils")

    # The first render does not wait for the checks
    assert html =~ ~s(aria-busy="true")

    html = render_async(view)
    assert html =~ ~s(aria-busy="false")
    assert has_element?(view, "[data-testid=system-check-tally]", "1 warning")
    assert has_element?(view, "li[data-check=healthy][data-status=ok] h3", "Healthy")
    assert has_element?(view, "li[data-check=warns][data-status=warning] small", "do the thing")
    assert has_element?(view, "li[data-check=warns] details li", "a")

    view |> element("#system-check button", "Run again") |> render_click()
    assert render_async(view) =~ ~s(aria-busy="false")
  end

  test "links a failing check to the screen that fixes it", %{conn: conn} do
    put_test_env(Brando.Doctor, skip: Brando.Doctor.default_checks() -- [Brando.Doctor.Checks.Modules])

    user = Brando.Factory.insert(:random_user)
    module = Brando.Factory.insert(:module)

    Brando.Repo.insert!(
      Ecto.Changeset.change(%Brando.Content.Block{}, %{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        module_id: module.id,
        module_version: nil,
        creator_id: user.id,
        sequence: 0
      })
    )

    {:ok, view, _html} = live(conn, "/admin/config/utils")
    render_async(view)

    assert has_element?(view, "li[data-check=modules] a[href$='/config/content/modules/stale-blocks']", "Resolve blocks")
  end

  describe "video providers" do
    setup do
      put_test_env(Brando.Doctor, skip: Brando.Doctor.default_checks() -- [Brando.Doctor.Checks.VideoProviders])
      put_test_env(Brando.Videos.Uploaders.Mux, [])
      put_test_env(Brando.Videos.Uploaders.Bunny, [])
      put_test_env(Brando.Videos.Uploaders.Cloudflare, [])
      put_test_env(Brando.Videos.Uploaders.Vimeo, [])
      put_test_env(:default_video_upload_strategy, :local)
      :ok
    end

    test "lists each problem the boot check finds as a warning", %{conn: conn} do
      put_test_env(:default_video_upload_strategy, :bunny)
      put_test_env(Brando.Videos.Uploaders.Mux, access_token_id: "id")

      {:ok, view, _html} = live(conn, "/admin/config/utils")
      render_async(view)

      assert has_element?(view, "li[data-check=video_providers][data-status=warning]")

      problems = Brando.Videos.ProviderConfigCheck.problems()
      assert length(problems) == 2

      for problem <- problems do
        assert has_element?(view, "li[data-check=video_providers] details li", problem)
      end
    end

    test "lists nothing when there are no problems", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/config/utils")
      render_async(view)

      assert has_element?(view, "li[data-check=video_providers][data-status=ok]")
      refute has_element?(view, "li[data-check=video_providers] details")
    end
  end

  test "Brando's own checks render", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/config/utils")
    render_async(view, 30_000)

    for id <- ~w(versions migrations oban configuration image_configs modules sitemap json_ld alt_text) do
      assert has_element?(view, "li[data-check=#{id}]")
    end

    # Which Brando is running, and from where
    assert has_element?(view, "li[data-check=versions] p", "Brando #{Brando.version()} (this checkout)")
  end
end
