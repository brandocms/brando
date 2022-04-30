Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Phoenix.DupHTMLController do
end

defmodule Phoenix.DupHTMLView do
end

defmodule Mix.Tasks.Brando.Gen.Test do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear()
    :ok
  end

  test "generates html resource" do
    in_tmp("brando.gen", fn ->
      Mix.Tasks.Brando.Install.run([])

      send(self(), {:mix_shell_input, :prompt, "Brando.BlueprintTest.Project"})
      Mix.Tasks.Brando.Gen.run([])

      assert File.exists?("lib/brando_admin/live/projects")

      assert_file("lib/brando_admin/live/projects/project_create_live.ex", fn file ->
        assert file =~ "BrandoIntegrationAdmin.Projects.ProjectCreateLive"
        assert file =~ "use BrandoAdmin.LiveView.Form, schema: Brando.Projects.Project"
        assert file =~ "<.live_component module={Form}\n      id=\"project_form\"\n"
      end)

      assert_file("lib/brando_admin/live/projects/project_update_live.ex", fn file ->
        assert file =~ "BrandoIntegrationAdmin.Projects.ProjectUpdateLive"
        assert file =~ "use BrandoAdmin.LiveView.Form, schema: Brando.Projects.Project"

        assert file =~
                 "<.live_component module={Form}\n      id=\"project_form\"\n      entry_id={@entry_id}\n"
      end)

      assert_file("lib/brando_admin/live/projects/project_list_live.ex", fn file ->
        assert file =~ "BrandoIntegrationAdmin.Projects.ProjectListLive"
        assert file =~ "use BrandoAdmin.LiveView.Listing, schema: Brando.Projects.Project"

        assert file =~
                 "<.live_component module={Content.List}\n      id={\"content_listing_\#{@schema}_default\"}\n"
      end)

      assert_file("lib/brando_web/views/project_view.ex", fn file ->
        assert file =~ "BrandoIntegrationWeb.ProjectView"
        assert file =~ "use Phoenix.Component"
        assert file =~ "def list_projects(assigns) do"
        assert file =~ "<%= for project <- @projects do %>"
      end)

      assert_file("lib/brando_web/templates/project/list.html.heex", fn file ->
        assert file =~ "<.list_projects projects={@projects} conn={@conn} />"
      end)

      assert_file("lib/brando_web/templates/project/detail.html.heex", fn file ->
        assert file =~ "<div class=\"project-header\">"
      end)
    end)
  end
end
