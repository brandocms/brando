defmodule Mix.Brando.Igniter.SiteRenderTest do
  # Compiles the files brando.gen.site plans for a phx.new application and
  # renders them, as the application would. Not async: it defines modules.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Phoenix.Template, only: [render_to_string: 4]

  alias Brando.IgniterCase

  @web "lib/render_site_web"

  setup_all do
    planned =
      [app: :render_site, module: "RenderSite"]
      |> IgniterCase.phoenix_project()
      |> Igniter.include_or_create_file("#{@web}/controllers/error_html.ex", """
      defmodule RenderSiteWeb.ErrorHTML do
        @moduledoc \"\"\"
        This module is invoked by your endpoint in case of errors on HTML requests.

        See config/config.exs.
        \"\"\"
        use RenderSiteWeb, :html

        def render(template, _assigns) do
          Phoenix.Controller.status_message_from_template(template)
        end
      end
      """)
      |> Igniter.compose_task(Mix.Tasks.Brando.Install, ["--public-site", "--replace-phoenix-home"])

    [] = planned.issues

    dir = Path.join(System.tmp_dir!(), "brando-site-render-#{System.unique_integer([:positive])}")

    files =
      for path <- [
            "#{@web}/cms/layouts.ex",
            "#{@web}/controllers/error_html.ex",
            "#{@web}/controllers/error_html/404.html.heex",
            "#{@web}/controllers/error_html/500.html.heex",
            "#{@web}/cms/lockdown_controller.ex",
            "#{@web}/cms/lockdown_html.ex"
          ] do
        file = Path.join(dir, path)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, IgniterCase.source(planned, path))
        file
      end

    {:ok, modules, _diagnostics} =
      files
      |> Enum.filter(&String.ends_with?(&1, ".ex"))
      |> Kernel.ParallelCompiler.compile(return_diagnostics: true)

    on_exit(fn ->
      File.rm_rf!(dir)

      for module <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end)

    :ok
  end

  # Compiled in setup_all, so not named literally: the compiler would warn.
  defp lockdown(conn, action, params) do
    conn = conn |> Plug.Test.init_test_session(%{}) |> Phoenix.Controller.put_format("html")
    Module.concat(RenderSiteWeb, CMS.LockdownController).call(%{conn | params: params}, action)
  end

  defp site_conn(conn), do: Phoenix.Controller.put_root_layout(conn, html: {RenderSiteWeb.CMS.Layouts, :root})

  test "a missing CMS page renders only the error, inside the layout it already has", %{conn: conn} do
    html = render_to_string(RenderSiteWeb.ErrorHTML, "404", "html", conn: site_conn(conn))
    assert html =~ ~s(class="error-page")
    assert html =~ "Page not found"
    refute html =~ "<html"
  end

  test "endpoint errors render the error inside the site's root layout", %{conn: conn} do
    for {status, text} <- [{"404", "Page not found"}, {"500", "Something went wrong"}] do
      html = render_to_string(RenderSiteWeb.ErrorHTML, status, "html", conn: conn)
      assert html =~ ~s(<html lang="en">)
      assert html =~ ~s(id="top")
      assert html =~ text
    end

    assert render_to_string(RenderSiteWeb.ErrorHTML, "401", "html", []) == "Unauthorized"
  end

  test "the lockdown page offers the password form only when a password is configured", %{conn: conn} do
    locked = lockdown(conn, :index, %{})
    assert locked.status == 200
    assert locked.resp_body =~ ~s(<meta name="robots" content="noindex")
    refute locked.resp_body =~ ~s(name="password")

    put_test_env(:lockdown_password, "open-sesame")
    form = lockdown(conn, :index, %{})
    assert form.resp_body =~ ~s(action="/coming-soon")
    assert form.resp_body =~ ~s(name="password")
  end

  test "the right password unlocks the session and a wrong one shows the form again", %{conn: conn} do
    put_test_env(:lockdown_password, "open-sesame")

    wrong = lockdown(conn, :unlock, %{"password" => "nope"})
    assert wrong.status == 401
    assert wrong.resp_body =~ ~s(role="alert")
    refute Plug.Conn.get_session(wrong, :lockdown_authorized)

    right = lockdown(conn, :unlock, %{"password" => "open-sesame"})
    assert Phoenix.ConnTest.redirected_to(right) == "/"
    assert Plug.Conn.get_session(right, :lockdown_authorized)
  end
end
