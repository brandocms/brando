Code.require_file "../../mix_helper.exs", __DIR__

defmodule Mix.Tasks.Brando.GenerateTest do
  use ExUnit.Case, async: true

  import MixHelper
  import ExUnit.CaptureIO

  @app_name  "photo_blog"
  @tmp_path  tmp_path()
  @project_path Path.join(@tmp_path, @app_name)

  setup_all do
    templates_path = Path.join([@project_path, "deps", "brando", "templates"])
    root_path =  File.cwd!

    #Clean up
    File.rm_rf @project_path

    #Create path for app
    File.mkdir_p Path.join(@project_path, "web")

    #Create path for templates
    File.mkdir_p templates_path

    #Copy templates into `deps/ashes/templates` to mimic a real Phoenix application
    File.cp_r! Path.join(root_path, "templates"), templates_path

    #Move into the project directory to run the generator
    File.cd! @project_path
  end

  test "brando.install" do
    assert String.contains?(capture_io(fn -> Mix.Tasks.Brando.Install.run([]) end), "Brando finished copying.")
    assert_file "web/controllers/auth_controller.ex"
    assert_file "web/controllers/admin/dashboard_controller.ex"
    assert File.exists?("web/views")
  end

  test "brando.install.static" do
    assert String.contains?(capture_io(fn -> Mix.Tasks.Brando.Install.Static.run([]) end), "Brando finished copying.")
    assert_file "priv/static/brando/css/brando.css"
    assert File.exists?("priv/static")
  end

  test "brando.install.headlines" do
    assert String.contains?(capture_io(fn -> Mix.Tasks.Brando.Install.Headlines.run([]) end), "Brando finished copying.")
  end
end