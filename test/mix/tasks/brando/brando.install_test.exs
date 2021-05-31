Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Brando.GenerateTest do
  use ExUnit.Case

  import MixHelper

  @app_name "photo_blog"
  @tmp_path tmp_path()
  @project_path Path.join(@tmp_path, @app_name)
  @root_path Path.expand(".")

  setup_all do
    templates_path = Path.join([@project_path, "deps", "brando", "lib", "web", "templates"])
    root_path = File.cwd!()

    # Clean up
    File.rm_rf(@project_path)

    # Create path for app
    File.mkdir_p(Path.join(@project_path, "brando"))

    # Create path for templates
    File.mkdir_p(templates_path)

    # Copy templates into `deps/ashes/templates`
    # to mimic a real Phoenix application
    File.cp_r!(Path.join([root_path, "lib", "web", "templates"]), templates_path)

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

    assert_file("lib/brando_web.ex", fn file ->
      assert file =~ "BrandoAdmin.Gettext"
    end)

    assert_file("config/runtime.exs", fn file ->
      assert file =~ ~s<url: System.get_env("BRANDO_DB_URL")>
    end)

    assert_file("mix.exs", fn file ->
      assert file =~ "defmodule Brando.MixProject do"
    end)

    assert_file("assets/frontend/package.json", fn file ->
      assert file =~ "brando Frontend"
    end)

    refute File.exists?("assets/css/app.css")
  end
end
