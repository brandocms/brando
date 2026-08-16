Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Brando.GenerateTest do
  use ExUnit.Case

  import MixHelper

  @app_name "photo_blog"
  @tmp_path tmp_path()
  @project_path Path.join(@tmp_path, @app_name)
  @root_path Path.expand(".")

  setup_all do
    templates_path =
      Path.join([@project_path, "deps", "brando", "lib", "brando_admin", "templates"])

    root_path = File.cwd!()

    # Clean up
    File.rm_rf(@project_path)

    # Create path for app
    File.mkdir_p(Path.join(@project_path, "brando"))

    # Create path for templates
    File.mkdir_p(templates_path)

    File.cp_r!(Path.join([root_path, "lib", "brando_admin", "templates"]), templates_path)

    # Move into the project directory to run the generator
    File.cd!(@project_path)

    on_exit(fn ->
      File.cd!(@root_path)
    end)
  end

  test "brando.install" do
    Mix.Tasks.Brando.Install.run([])
    assert_received {:mix_shell, :info, ["\nBrando finished copying."]}
    assert File.exists?("lib/brando_web/villain")
    assert_file("lib/brando_web/villain/parser.ex")

    assert_file("config/runtime.exs", fn file ->
      assert file =~ ~s<url: System.get_env("BRANDO_DB_URL")>
    end)

    assert_file("config/brando.exs", fn file ->
      assert file =~ "tenancy_mode: :none"
      refute file =~ "site_key:"
    end)

    assert_file("lib/brando_web/components/layouts.ex", fn file ->
      assert file =~ "embed_templates \"layouts/*\""
      assert file =~ "embed_templates \"partials/*\""
    end)

    assert_file("mix.exs", fn file ->
      assert file =~ "defmodule Brando.MixProject do"
    end)

    assert_file("assets/frontend/package.json", fn file ->
      assert file =~ "brando Frontend"
    end)

    assert_file("lib/brando_admin/live/dashboard_live.ex", fn file ->
      assert file =~ "use BrandoAdmin.LiveView.Listing, schema: nil"
    end)

    refute File.exists?("assets/css/app.css")
  end

  test "parses valid installer tenancy options" do
    assert Mix.Tasks.Brando.Install.parse_tenancy_options!([]) == %{
             mode: :none,
             site_key: nil
           }

    assert Mix.Tasks.Brando.Install.parse_tenancy_options!(
             tenancy_mode: "single",
             site_key: "photo-blog"
           ) == %{mode: :single, site_key: "photo-blog"}

    assert Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "multi") == %{
             mode: :multi,
             site_key: nil
           }
  end

  test "renders single-site tenancy configuration" do
    config =
      "templates/brando.install/config/brando.exs"
      |> Mix.Tasks.Brando.Install.render()
      |> EEx.eval_string(
        application_name: "photo_blog",
        application_module: "PhotoBlog",
        tenancy_mode: :single,
        site_key: "photo-blog"
      )

    assert config =~ "tenancy_mode: :single"
    assert config =~ ~s(site_key: "photo-blog")
  end

  test "rejects incomplete or contradictory installer tenancy options" do
    assert_raise Mix.Error, ~r/--site-key is required/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "single")
    end

    assert_raise Mix.Error, ~r/--site-key can only be used/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(site_key: "photo-blog")
    end

    assert_raise Mix.Error, ~r/Invalid --tenancy-mode/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "global")
    end
  end
end
