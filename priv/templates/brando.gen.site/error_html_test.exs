defmodule <%= web_module %>.ErrorHTMLTest do
  use <%= web_module %>.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  # A missing CMS page renders inside the site's root layout, so the page
  # renders only its content here.
  defp site_conn, do: Phoenix.Controller.put_root_layout(build_conn(), html: {<%= web_module %>.CMS.Layouts, :root})

  test "renders 404.html" do
    assert render_to_string(<%= web_module %>.ErrorHTML, "404", "html", conn: site_conn()) =~ ~s(class="error-page")
  end

  test "renders 500.html" do
    assert render_to_string(<%= web_module %>.ErrorHTML, "500", "html", conn: site_conn()) =~ ~s(class="error-page")
  end

  test "renders other statuses as their status message" do
    assert render_to_string(<%= web_module %>.ErrorHTML, "401", "html", []) == "Unauthorized"
  end
end
